import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// Sipflix: measures the real client↔server throughput so the "Auto" quality
/// setting can pick a bitrate ceiling that matches the connection instead of
/// guessing.
///
/// Uses Emby's `/emby/Playback/BitrateTest?Size=N` endpoint (verified on
/// AlphaV2: returns exactly N bytes, HTTP 200), and measures only the **steady
/// state** of the transfer:
///
///  * TTFB is excluded — DNS + TCP + TLS + server think time is ~0.7s on a VN→EU
///    link and would otherwise be counted as "slow bandwidth".
///  * The first [_warmupBytes] are discarded — TCP slow-start means a small
///    sample reads far below the true link speed (measured on the same link:
///    2 MB → 5.3 Mbps, 5 MB → 11.5 Mbps, 10 MB → 20.4 Mbps naive / 25.1 Mbps
///    transfer-only).
///
/// The request is **cancelled** as soon as enough clean samples are collected,
/// so a probe costs a few MB rather than the full payload — it must never
/// compete with customers' streams for bandwidth.
class SipflixBandwidthProbe {
  SipflixBandwidthProbe({Dio? dio, Logger? logger})
      : _dio = dio ?? Dio(),
        _logger = logger ?? Logger();

  final Dio _dio;
  final Logger _logger;

  /// For same-library extensions (preflight's measureRoute).
  Dio get dio => _dio;

  /// Upper bound on what a single probe may download.
  static const int _probeBytes = 16000000;

  /// Discarded before timing starts (TCP slow-start / CDN cache fill).
  static const int _warmupBytes = 2000000;

  /// How long to measure once warmed up. Long enough to be stable, short enough
  /// to stay cheap on a fast link.
  static const Duration _measureWindow = Duration(seconds: 3);

  /// Hard ceiling for the whole probe.
  static const Duration _overallTimeout = Duration(seconds: 20);

  /// Measures throughput in Mbps, or null if it could not be measured (offline,
  /// endpoint missing, timeout, too little data). Never throws.
  Future<double?> measureMbps({
    required String baseUrl,
    required String? accessToken,
  }) async {
    if (accessToken == null || accessToken.isEmpty) return null;
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = '$root/emby/Playback/BitrateTest?Size=$_probeBytes';
    final cancelToken = CancelToken();

    try {
      final response = await _dio
          .get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              headers: {
                'X-Emby-Token': accessToken,
                'Authorization': 'MediaBrowser Token="$accessToken"',
              },
              // Per-chunk idle timeout; the overall budget is enforced below.
              receiveTimeout: _overallTimeout,
            ),
            cancelToken: cancelToken,
          )
          .timeout(_overallTimeout);

      final body = response.data;
      if (body == null) return null;

      var totalBytes = 0;
      var measuredBytes = 0;
      Stopwatch? window;
      final completer = Completer<double?>();
      late final StreamSubscription<List<int>> sub;

      void finish(double? result) {
        if (completer.isCompleted) return;
        completer.complete(result);
        // Stop pulling data: the probe only needs its sample, not the payload.
        unawaited(sub.cancel());
        if (!cancelToken.isCancelled) cancelToken.cancel('probe complete');
      }

      double? computeMbps() {
        final elapsedUs = window?.elapsedMicroseconds ?? 0;
        if (measuredBytes <= 0 || elapsedUs <= 0) return null;
        return (measuredBytes * 8) / (elapsedUs / 1000000) / 1000000;
      }

      sub = body.stream.listen(
        (chunk) {
          totalBytes += chunk.length;
          if (window == null) {
            // Still warming up; timing starts after the slow-start bytes.
            if (totalBytes >= _warmupBytes) window = Stopwatch()..start();
            return;
          }
          measuredBytes += chunk.length;
          if (window!.elapsed >= _measureWindow || totalBytes >= _probeBytes) {
            finish(computeMbps());
          }
        },
        onDone: () => finish(computeMbps()),
        onError: (Object e) {
          _logger.d('Sipflix bandwidth probe stream error: $e');
          finish(computeMbps());
        },
        cancelOnError: true,
      );

      final result = await completer.future.timeout(
        _overallTimeout,
        onTimeout: () {
          finish(null);
          return computeMbps();
        },
      );
      if (result == null || result <= 0 || !result.isFinite) return null;
      _logger.i('Sipflix bandwidth probe: ${result.toStringAsFixed(1)} Mbps '
          '(${measuredBytes ~/ 1000} kB sampled)');
      return result;
    } catch (e) {
      _logger.d('Sipflix bandwidth probe failed: $e');
      if (!cancelToken.isCancelled) cancelToken.cancel('probe failed');
      return null;
    }
  }
}

/// Burst + sustained throughput for one connection route, as measured by
/// [SipflixBandwidthProbe.measureRoute].
class SipflixRouteMeasurement {
  /// Best throughput over any 500 ms window — what a full buffer can bank.
  final double burstMbps;

  /// Steady-state throughput after TCP slow-start — what playback can rely on.
  final double sustainedMbps;

  const SipflixRouteMeasurement({
    required this.burstMbps,
    required this.sustainedMbps,
  });
}

extension SipflixRouteProbing on SipflixBandwidthProbe {
  /// Preflight measurement of one route: burst (best 500 ms window, sampled
  /// from the very first byte so slow-start peaks count) AND sustained (the
  /// same warm-then-measure method [SipflixBandwidthProbe.measureMbps] uses).
  /// Cancels the transfer as soon as both numbers exist. [isCancelled] lets the
  /// preflight screen abort between chunks (skip / turn-off). Never throws;
  /// null when the route could not be measured at all.
  Future<SipflixRouteMeasurement?> measureRoute({
    required String baseUrl,
    required String? accessToken,
    bool Function()? isCancelled,
  }) async {
    if (accessToken == null || accessToken.isEmpty) return null;
    final root =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    const probeBytes = 16000000;
    const warmupBytes = 2000000;
    const burstWindow = Duration(milliseconds: 500);
    const sustainWindow = Duration(milliseconds: 2500);
    const overallTimeout = Duration(seconds: 10);
    final url = '$root/emby/Playback/BitrateTest?Size=$probeBytes';
    final cancelToken = CancelToken();

    try {
      final response = await dio
          .get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              headers: {
                'X-Emby-Token': accessToken,
                'Authorization': 'MediaBrowser Token="$accessToken"',
              },
              receiveTimeout: overallTimeout,
            ),
            cancelToken: cancelToken,
          )
          .timeout(overallTimeout);
      final body = response.data;
      if (body == null) return null;

      // (timestampUs, cumulativeBytes) samples drive a sliding-window burst
      // scan; sustained uses only bytes past the warm-up mark.
      final clock = Stopwatch()..start();
      final samples = <(int, int)>[];
      var total = 0;
      var sustainedStartUs = -1;
      var sustainedStartBytes = 0;
      double? sustained;
      final done = Completer<void>();
      late final StreamSubscription<List<int>> sub;

      void finish() {
        if (!done.isCompleted) done.complete();
        unawaited(sub.cancel());
        if (!cancelToken.isCancelled) cancelToken.cancel('measured');
      }

      sub = body.stream.listen(
        (chunk) {
          if (isCancelled?.call() == true) {
            finish();
            return;
          }
          total += chunk.length;
          final nowUs = clock.elapsedMicroseconds;
          samples.add((nowUs, total));
          if (total >= warmupBytes && sustainedStartUs < 0) {
            sustainedStartUs = nowUs;
            sustainedStartBytes = total;
          }
          if (sustainedStartUs >= 0 &&
              nowUs - sustainedStartUs >= sustainWindow.inMicroseconds) {
            final bytes = total - sustainedStartBytes;
            final secs = (nowUs - sustainedStartUs) / 1e6;
            sustained = bytes * 8 / secs / 1e6;
            finish();
          } else if (total >= probeBytes) {
            finish();
          }
        },
        onDone: finish,
        onError: (Object _) => finish(),
        cancelOnError: true,
      );
      await done.future.timeout(overallTimeout, onTimeout: finish);

      if (samples.length < 2) return null;
      // Sustained fallback when the transfer ended before a full window: use
      // whatever post-warm-up stretch exists, else the whole transfer.
      if (sustained == null) {
        final lastUs = samples.last.$1;
        if (sustainedStartUs >= 0 && lastUs > sustainedStartUs) {
          final bytes = samples.last.$2 - sustainedStartBytes;
          sustained = bytes * 8 / ((lastUs - sustainedStartUs) / 1e6) / 1e6;
        } else {
          sustained = samples.last.$2 * 8 / (lastUs / 1e6) / 1e6;
        }
      }

      // Burst: best throughput across any window of >= burstWindow.
      var burst = 0.0;
      var lo = 0;
      for (var hi = 1; hi < samples.length; hi++) {
        while (samples[hi].$1 - samples[lo].$1 > burstWindow.inMicroseconds &&
            lo < hi - 1) {
          lo++;
        }
        final dtUs = samples[hi].$1 - samples[lo].$1;
        if (dtUs >= burstWindow.inMicroseconds ~/ 2) {
          final mbps = (samples[hi].$2 - samples[lo].$2) * 8 / (dtUs / 1e6) / 1e6;
          if (mbps > burst) burst = mbps;
        }
      }
      final s = sustained;
      if (s == null || !s.isFinite || s <= 0) return null;
      if (burst < s) burst = s;
      return SipflixRouteMeasurement(burstMbps: burst, sustainedMbps: s);
    } catch (_) {
      if (!cancelToken.isCancelled) cancelToken.cancel('failed');
      return null;
    }
  }
}
