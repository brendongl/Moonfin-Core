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
