import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import 'sipflix_log.dart';

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
        _logger = logger ?? sipflixLogger();

  final Dio _dio;
  final Logger _logger;

  /// For same-library extensions (preflight's measureRoute).
  Dio get dio => _dio;

  /// One line per route probe, with the counters behind the verdict.
  void _logRoute({
    required String url,
    required int totalBytes,
    required int elapsedUs,
    required int firstByteUs,
    required int sampleCount,
    required int sustainedStartUs,
    required int sustainedBytes,
    required double? sustainedMbps,
    required double burstMbps,
  }) {
    final host = Uri.tryParse(url)?.host ?? url;
    final wall = elapsedUs / 1e6;
    final naive = wall > 0 ? totalBytes * 8 / wall / 1e6 : 0.0;
    final line =
      'Sipflix probe $host: ${(totalBytes / 1e6).toStringAsFixed(1)} MB in '
      '${wall.toStringAsFixed(2)}s (naive ${naive.toStringAsFixed(1)} Mbps), '
      'ttfb ${(firstByteUs / 1000).toStringAsFixed(0)}ms, '
      'chunks $sampleCount, '
      'sustained window ${(sustainedBytes / 1e6).toStringAsFixed(1)} MB from '
      '${(sustainedStartUs / 1e6).toStringAsFixed(2)}s '
      '=> ${sustainedMbps?.toStringAsFixed(1) ?? "null"} Mbps sustained, '
      '${burstMbps.toStringAsFixed(1)} burst';
    _logger.i(line);
    // Also into the in-app log, because the box's owner cannot read logcat.
    sipflixDiag(line);
  }

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
  ///
  /// Runs in a background isolate for the same reason the per-route probe does:
  /// on the UI isolate it shares the event loop with rendering and ends up
  /// timing its own frame budget rather than the link. This one under-read by
  /// 2-3x (8.9 and 11.5 Mbps against a 22-30 Mbps link, operator-measured
  /// 2026-08-22) rather than the 20x the preflight probe managed, because it
  /// runs at startup when less is being drawn — same fault, gentler conditions.
  Future<double?> measureMbps({
    required String baseUrl,
    required String? accessToken,
  }) async {
    if (accessToken == null || accessToken.isEmpty) return null;
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = '$root/emby/Playback/BitrateTest?Size=$_probeBytes';

    try {
      final raw = await sipflixRunProbeIsolate(
        [
          url,
          accessToken,
          _probeBytes,
          _warmupBytes,
          _measureWindow.inMicroseconds,
          _overallTimeout.inMilliseconds,
          500000,
        ],
        hardDeadline: _overallTimeout + const Duration(seconds: 5),
      );
      if (raw == null) return null;
      final sustained = raw['sustained'] ?? 0;
      if (sustained <= 0 || !sustained.isFinite) return null;
      _logRoute(
        url: root,
        totalBytes: (raw['bytes'] ?? 0).toInt(),
        elapsedUs: (raw['elapsedUs'] ?? 0).toInt(),
        firstByteUs: 0,
        sampleCount: 0,
        sustainedStartUs: 0,
        sustainedBytes: (raw['bytes'] ?? 0).toInt(),
        sustainedMbps: sustained,
        burstMbps: raw['burst'] ?? sustained,
      );
      return sustained;
    } catch (e) {
      _logger.d('Sipflix bandwidth probe failed: $e');
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

/// Pure sampling math, shared by the isolate worker and its tests.
/// [samples] is (elapsedMicroseconds, cumulativeBytes), oldest first.
({double burstMbps, double sustainedMbps})? sipflixThroughputFrom({
  required List<(int, int)> samples,
  required int warmupBytes,
  required int burstWindowUs,
}) {
  if (samples.length < 2) return null;

  // Sustained: everything after the warm-up mark, so TCP slow-start is not
  // counted as the link being slow.
  var startUs = -1;
  var startBytes = 0;
  for (final s in samples) {
    if (s.$2 >= warmupBytes) {
      startUs = s.$1;
      startBytes = s.$2;
      break;
    }
  }
  final last = samples.last;
  double sustained;
  if (startUs >= 0 && last.$1 > startUs) {
    sustained = (last.$2 - startBytes) * 8 / ((last.$1 - startUs) / 1e6) / 1e6;
  } else if (last.$1 > 0) {
    // Never reached the warm-up mark: all we can honestly report is the whole
    // transfer, and the caller should treat that as low confidence.
    sustained = last.$2 * 8 / (last.$1 / 1e6) / 1e6;
  } else {
    return null;
  }

  // Burst: best throughput across any window of at least burstWindowUs/2.
  var burst = 0.0;
  var lo = 0;
  for (var hi = 1; hi < samples.length; hi++) {
    while (samples[hi].$1 - samples[lo].$1 > burstWindowUs && lo < hi - 1) {
      lo++;
    }
    final dtUs = samples[hi].$1 - samples[lo].$1;
    if (dtUs >= burstWindowUs ~/ 2) {
      final mbps = (samples[hi].$2 - samples[lo].$2) * 8 / (dtUs / 1e6) / 1e6;
      if (mbps > burst) burst = mbps;
    }
  }
  if (!sustained.isFinite || sustained <= 0) return null;
  if (burst < sustained) burst = sustained;
  return (burstMbps: burst, sustainedMbps: sustained);
}

/// Runs INSIDE a background isolate.
///
/// The probe used to stream on the UI isolate, where it had to share the event
/// loop with rendering. On an Allwinner box that starved the socket reader:
/// measured 2026-08-21 on Max16, three different routes each delivered only
/// ~1.8 MB in a full 10 s (~1.5 Mbps, ~65 chunks/s — suspiciously close to the
/// frame rate) while `wget` on the SAME box at the SAME moment pulled 16 MB in
/// 6.5 s. TCP backs off when the receiver does not drain, so the app measured
/// its own event loop rather than the link. A dedicated isolate has nothing
/// else to do.
Future<Map<String, double>?> sipflixProbeWorker(List<Object> args) async {
  final url = args[0] as String;
  final token = args[1] as String;
  final probeBytes = args[2] as int;
  final warmupBytes = args[3] as int;
  final sustainUs = args[4] as int;
  final timeoutMs = args[5] as int;
  final burstWindowUs = args[6] as int;

  // One wall-clock budget for the whole attempt. A route that accepts the TCP
  // connection and then stalls used to cost nothing here — the deadline was
  // only read when a chunk ARRIVED, and the header wait had no bound at all —
  // so a blackholed CDN edge ran until the caller's outer timeout.
  final wall = Stopwatch()..start();
  Duration remaining() {
    final left = timeoutMs - wall.elapsedMilliseconds;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..autoUncompress = false;
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(remaining());
    request.headers.set('X-Emby-Token', token);
    request.headers.set('Authorization', 'MediaBrowser Token="$token"');
    // Compressed bytes would be counted against wall time and under-report a
    // payload that is mostly zeroes.
    request.headers.set('Accept-Encoding', 'identity');
    final response = await request.close().timeout(remaining());
    if (response.statusCode >= 400) return null;

    final clock = Stopwatch()..start();
    final samples = <(int, int)>[];
    var total = 0;
    var sustainedStartUs = -1;

    final body = response.timeout(
      remaining(),
      onTimeout: (sink) => sink.close(),
    );
    await for (final chunk in body) {
      total += chunk.length;
      final nowUs = clock.elapsedMicroseconds;
      samples.add((nowUs, total));
      if (total >= warmupBytes && sustainedStartUs < 0) sustainedStartUs = nowUs;
      final haveWindow =
          sustainedStartUs >= 0 && nowUs - sustainedStartUs >= sustainUs;
      if (haveWindow || total >= probeBytes || remaining() == Duration.zero) {
        break;
      }
    }

    final result = sipflixThroughputFrom(
      samples: samples,
      warmupBytes: warmupBytes,
      burstWindowUs: burstWindowUs,
    );
    if (result == null) return null;
    return {
      'burst': result.burstMbps,
      'sustained': result.sustainedMbps,
      'bytes': total.toDouble(),
      'elapsedUs': samples.isEmpty ? 0 : samples.last.$1.toDouble(),
    };
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Entry point for the killable probe isolate. [args] is [replyPort, ...the
/// argument list [sipflixProbeWorker] takes].
Future<void> _sipflixProbeEntry(List<Object> args) async {
  final reply = args[0] as SendPort;
  Map<String, double>? out;
  try {
    out = await sipflixProbeWorker(args.sublist(1));
  } catch (_) {
    out = null;
  }
  reply.send(out);
}

/// Runs [sipflixProbeWorker] in an isolate that can actually be stopped.
///
/// `Isolate.run(...).timeout(...)` abandons the future but leaves the isolate
/// downloading, so neither the preflight's Skip nor the per-route deadline had
/// any effect on the transfer — the box kept pulling up to 16 MB with nobody
/// waiting for it. Spawning the isolate directly means [hardDeadline] and
/// [isCancelled] can kill it. Never throws; null when nothing was measured.
Future<Map<String, double>?> sipflixRunProbeIsolate(
  List<Object> args, {
  required Duration hardDeadline,
  bool Function()? isCancelled,
}) async {
  // Ticks from before the spawn, so the caller's per-route budget covers the
  // isolate bring-up too — on an Allwinner box that is not free.
  final since = Stopwatch()..start();
  final port = ReceivePort();
  final errors = ReceivePort();
  Isolate isolate;
  try {
    isolate = await Isolate.spawn(
      _sipflixProbeEntry,
      [port.sendPort, ...args],
      onError: errors.sendPort,
      onExit: port.sendPort,
      errorsAreFatal: true,
    );
  } catch (_) {
    port.close();
    errors.close();
    return null;
  }

  final done = Completer<Map<String, double>?>();
  void finish(Map<String, double>? value) {
    if (!done.isCompleted) done.complete(value);
  }

  // onExit also posts here (as null), so a worker that dies without answering
  // still completes instead of waiting out the deadline.
  final sub = port.listen((msg) {
    finish(msg is Map ? msg.cast<String, double>() : null);
  });
  final errSub = errors.listen((_) => finish(null));
  final left = hardDeadline - since.elapsed;
  final deadline = Timer(
    left.isNegative ? Duration.zero : left,
    () => finish(null),
  );
  Timer? cancelPoll;
  if (isCancelled != null) {
    cancelPoll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (isCancelled()) finish(null);
    });
  }

  try {
    return await done.future;
  } finally {
    deadline.cancel();
    cancelPoll?.cancel();
    isolate.kill(priority: Isolate.immediate);
    await sub.cancel();
    await errSub.cancel();
    port.close();
    errors.close();
  }
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
    if (isCancelled?.call() == true) return null;
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    const probeBytes = 16000000;
    const warmupBytes = 2000000;
    const burstWindowUs = 500000;
    const sustainUs = 2500000;
    // Leaves the isolate spawn and hand-back inside the caller's 10s per-route
    // cap, which [SipflixPreflightController.overallTimeout] is derived from.
    const timeoutMs = 9000;
    const hardDeadlineMs = 10000;
    final url = '$root/emby/Playback/BitrateTest?Size=$probeBytes';

    try {
      // Off the UI isolate on purpose — see [sipflixProbeWorker].
      final raw = await sipflixRunProbeIsolate(
        [
          url,
          accessToken,
          probeBytes,
          warmupBytes,
          sustainUs,
          timeoutMs,
          burstWindowUs,
        ],
        hardDeadline: const Duration(milliseconds: hardDeadlineMs),
        isCancelled: isCancelled,
      );
      if (raw == null) return null;

      final sustained = raw['sustained'] ?? 0;
      final burst = raw['burst'] ?? 0;
      final bytes = (raw['bytes'] ?? 0).toInt();
      final elapsedUs = (raw['elapsedUs'] ?? 0).toInt();
      _logRoute(
        url: root,
        totalBytes: bytes,
        elapsedUs: elapsedUs,
        firstByteUs: 0,
        sampleCount: 0,
        sustainedStartUs: bytes >= warmupBytes ? 0 : -1,
        sustainedBytes: bytes,
        sustainedMbps: sustained,
        burstMbps: burst,
      );
      if (sustained <= 0 || !sustained.isFinite) return null;
      return SipflixRouteMeasurement(
        burstMbps: burst,
        sustainedMbps: sustained,
      );
    } catch (e) {
      _logger.w('Sipflix route probe failed for $root: $e');
      return null;
    }
  }
}
