import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:playback_core/playback_core.dart';

import '../auth/repositories/server_repository.dart';
import '../data/models/aggregated_item.dart';
import '../data/services/connectivity_service.dart';
import '../data/services/media_server_client_factory.dart';
import '../preference/user_preferences.dart';
import '../ui/navigation/app_router.dart';
import 'sipflix_bandwidth_probe.dart';
import 'sipflix_bitrate_watchdog.dart';
import 'sipflix_connection_manager.dart';
import 'sipflix_servers.dart';

/// Sipflix "Stream Preflight": an opt-in, per-play connection check.
///
/// When enabled, EVERY new-item playback start (play button, next/previous,
/// auto-next — wired via [PlaybackManager.preflightHook]) first shows a
/// full-screen "Optimising your stream…" page while both connection routes are
/// speed-tested with a real download (burst + sustained). The route that can
/// actually carry the file wins and playback direct-plays there; when neither
/// can, the best route is kept and the quality is capped to what it sustained,
/// so the server transcodes to something watchable instead of buffering.
///
/// Deliberately runs EVERY time (operator spec): links here change hour to
/// hour, and a resume the next evening should not trust yesterday's numbers.
class SipflixPreflightController {
  SipflixPreflightController({SipflixBandwidthProbe? probe, Logger? logger})
      : _probe = probe ?? SipflixBandwidthProbe(),
        _logger = logger ?? Logger();

  final SipflixBandwidthProbe _probe;
  final Logger _logger;

  /// Media kinds worth testing. Live TV rides the Dispatcharr pipeline and
  /// trailers/prerolls are throwaway — neither gets a 10s gate.
  static const Set<String> _eligibleTypes = {
    'Movie',
    'Episode',
    'Video',
    'MusicVideo',
  };

  /// Headroom over the file's own bitrate a route must sustain for DirectPlay.
  static const double requirementHeadroom = 1.2;

  /// Fraction of sustained throughput a transcode cap may use.
  static const double capHeadroom = 0.8;

  /// The whole preflight (UI + both probes + apply) is capped here; timeout
  /// means "play normally", never a stuck loading screen.
  static const Duration overallTimeout = Duration(seconds: 12);

  /// Watchdog fires this session (for the enable-offer prompt).
  int watchdogFireCount = 0;

  bool _running = false;

  /// The [PlaybackManager.preflightHook] entry point.
  Future<PlaybackPreflightResult?> runForItem(dynamic item) async {
    final prefs = GetIt.instance<UserPreferences>();
    if (!prefs.get(UserPreferences.preflightEnabled)) return null;
    if (_running) return null;
    if (item is! AggregatedItem) return null;
    if (!_eligibleTypes.contains(item.type)) return null;
    if (item.rawData['__moonfinIsPreroll'] == true) return null;
    if (!SipflixServers.isSipflixServer(item.serverId)) return null;
    if (!GetIt.instance<ConnectivityService>().isOnline) return null;

    _running = true;
    try {
      return await _run(item).timeout(overallTimeout, onTimeout: () {
        _logger.w('Sipflix preflight timed out — playing normally');
        return null;
      });
    } catch (e) {
      _logger.w('Sipflix preflight failed: $e');
      return null;
    } finally {
      _running = false;
    }
  }

  Future<PlaybackPreflightResult?> _run(AggregatedItem item) async {
    final factory = GetIt.instance<MediaServerClientFactory>();
    final client = factory.getClientIfExists(item.serverId);
    final token = client?.accessToken;
    if (client == null || token == null || token.isEmpty) return null;

    final requiredMbps = _requiredMbpsFor(item);
    final progress = SipflixPreflightProgress(
      itemName: item.name,
      requiredMbps: requiredMbps,
      routes: SipflixServers.routeChoices,
    );

    final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
    _PreflightPage? page;
    if (navContext != null && navContext.mounted) {
      page = _PreflightPage(progress: progress);
      unawaited(
        showDialog<void>(
          context: navContext,
          barrierDismissible: false,
          barrierColor: Colors.black,
          useSafeArea: false,
          builder: (_) => page!,
        ),
      );
    }

    try {
      final results = <({SipflixRouteDef route, SipflixRouteMeasurement m})>[];
      for (final route in SipflixServers.routeChoices) {
        if (progress.aborted) break;
        progress.markTesting(route.id);
        final m = await _probe.measureRoute(
          baseUrl: route.url,
          accessToken: token,
          isCancelled: () => progress.aborted,
        );
        if (m != null) {
          results.add((route: route, m: m));
          progress.markResult(route.id, m);
        } else {
          progress.markFailed(route.id);
        }
      }
      if (progress.aborted || results.isEmpty) return null;

      final decision = decide(
        results: results,
        requiredMbps: requiredMbps,
        tiers: SipflixBitrateWatchdog.tiers,
      );
      progress.markDecision(decision);

      // Apply the route in place: persist the address AND retarget the live
      // client, so the resolve that follows uses the winning route without any
      // client teardown mid-flight.
      final serverRepo = GetIt.instance<ServerRepository>();
      final server = serverRepo.servers
          .where((s) => s.id == item.serverId)
          .firstOrNull;
      if (server != null &&
          SipflixConnectionManager.currentRoute(server).id !=
              decision.route.id) {
        await serverRepo.updateServer(
          server.copyWith(address: decision.route.url),
        );
        client.baseUrl = decision.route.url;
        _logger.i('Sipflix preflight: switched route to ${decision.route.id}');
      }

      // Keep the adaptive-Auto store coherent with what was just measured.
      await GetIt.instance<UserPreferences>()
          .set(UserPreferences.measuredBandwidthMbps, decision.sustainedMbps);
      await GetIt.instance<UserPreferences>().set(
        UserPreferences.measuredBandwidthAt,
        DateTime.now().millisecondsSinceEpoch,
      );

      // Let the verdict be readable for a beat before playback takes over.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return PlaybackPreflightResult(capMbps: decision.capMbps);
    } finally {
      page?.close();
    }
  }

  static double _requiredMbpsFor(AggregatedItem item) {
    var bps = 0;
    for (final source in item.mediaSources) {
      final rate = source['Bitrate'];
      if (rate is int && rate > bps) bps = rate;
    }
    if (bps <= 0) return 10;
    return bps * requirementHeadroom / 1e6;
  }

  /// Pure decision: DirectPlay on the fastest route that sustains the
  /// requirement, else best route + the highest tier its sustained rate covers.
  static SipflixPreflightDecision decide({
    required List<({SipflixRouteDef route, SipflixRouteMeasurement m})> results,
    required double requiredMbps,
    required List<int> tiers,
  }) {
    final sorted = [...results]
      ..sort((a, b) => b.m.sustainedMbps.compareTo(a.m.sustainedMbps));
    final best = sorted.first;
    final canDirect = best.m.sustainedMbps >= requiredMbps;
    if (canDirect) {
      return SipflixPreflightDecision(
        route: best.route,
        capMbps: null,
        sustainedMbps: best.m.sustainedMbps,
        direct: true,
      );
    }
    final budget = best.m.sustainedMbps * capHeadroom;
    var cap = tiers.last;
    for (final tier in tiers) {
      if (tier <= budget) {
        cap = tier;
        break;
      }
    }
    return SipflixPreflightDecision(
      route: best.route,
      capMbps: cap,
      sustainedMbps: best.m.sustainedMbps,
      direct: false,
    );
  }
}

class SipflixPreflightDecision {
  final SipflixRouteDef route;
  final int? capMbps;
  final double sustainedMbps;
  final bool direct;

  const SipflixPreflightDecision({
    required this.route,
    required this.capMbps,
    required this.sustainedMbps,
    required this.direct,
  });
}

/// Live state the preflight page renders; mutated by the controller.
class SipflixPreflightProgress extends ChangeNotifier {
  final String itemName;
  final double requiredMbps;
  final List<SipflixRouteDef> routes;

  final Map<String, SipflixRouteMeasurement?> results = {};
  String? testingRouteId;
  SipflixPreflightDecision? decision;
  bool aborted = false;

  SipflixPreflightProgress({
    required this.itemName,
    required this.requiredMbps,
    required this.routes,
  });

  void markTesting(String routeId) {
    testingRouteId = routeId;
    notifyListeners();
  }

  void markResult(String routeId, SipflixRouteMeasurement m) {
    results[routeId] = m;
    testingRouteId = null;
    notifyListeners();
  }

  void markFailed(String routeId) {
    results[routeId] = null;
    testingRouteId = null;
    notifyListeners();
  }

  void markDecision(SipflixPreflightDecision d) {
    decision = d;
    notifyListeners();
  }

  void abort() {
    aborted = true;
    notifyListeners();
  }
}

/// Full-screen preflight page. OK short-press skips this one check; holding OK
/// for [_holdToDisable] turns the feature off entirely (operator spec); Back
/// skips. Closes itself when the controller finishes.
class _PreflightPage extends StatefulWidget {
  final SipflixPreflightProgress progress;

  const _PreflightPage({required this.progress});

  void close() => _state?._close();

  static _PreflightPageState? _state;

  @override
  // ignore: no_logic_in_create_state
  State<_PreflightPage> createState() {
    return _state = _PreflightPageState();
  }
}

class _PreflightPageState extends State<_PreflightPage> {
  static const _holdToDisable = Duration(milliseconds: 1200);
  DateTime? _selectDownAt;
  bool _closed = false;

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  void _skip() {
    widget.progress.abort();
    _close();
  }

  Future<void> _disableFeature() async {
    await GetIt.instance<UserPreferences>()
        .set(UserPreferences.preflightEnabled, false);
    _skip();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isSelect = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;
    if (isSelect) {
      if (event is KeyDownEvent) {
        _selectDownAt ??= DateTime.now();
      } else if (event is KeyUpEvent) {
        final downAt = _selectDownAt;
        _selectDownAt = null;
        if (downAt != null &&
            DateTime.now().difference(downAt) >= _holdToDisable) {
          unawaited(_disableFeature());
        } else {
          _skip();
        }
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.escape)) {
      _skip();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (identical(_PreflightPage._state, this)) _PreflightPage._state = null;
    super.dispose();
  }

  String _routeLine(SipflixRouteDef route) {
    final p = widget.progress;
    if (p.testingRouteId == route.id) return '${route.label}: testing…';
    if (!p.results.containsKey(route.id)) return '${route.label}: waiting';
    final m = p.results[route.id];
    if (m == null) return '${route.label}: unavailable';
    return '${route.label}: ${m.sustainedMbps.toStringAsFixed(1)} Mbps '
        '(burst ${m.burstMbps.toStringAsFixed(0)})';
  }

  String? _verdictLine() {
    final d = widget.progress.decision;
    if (d == null) return null;
    if (d.direct) return 'Full quality on ${d.route.label}';
    return '${d.route.label} at ${d.capMbps} Mbps for smooth playback';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.black,
        child: AnimatedBuilder(
          animation: widget.progress,
          builder: (context, _) {
            final verdict = _verdictLine();
            return Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/sipflix_badge.png',
                        width: 96,
                        height: 96,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.network_check,
                          size: 72,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Optimising your stream…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Checking the fastest connection for '
                        '${widget.progress.itemName}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 28),
                      for (final route in widget.progress.routes)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            _routeLine(route),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (verdict != null)
                        Text(
                          verdict,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        const SizedBox(
                          width: 160,
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                    ],
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 28,
                  child: Text(
                    'Press OK to skip  •  Hold OK to turn off  •  '
                    'Settings > Stream Preflight',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Once-a-day dialog offering to enable Stream Preflight after playback has
/// struggled repeatedly. Called from the player's watchdog path.
Future<void> maybeOfferPreflight() async {
  final prefs = GetIt.instance<UserPreferences>();
  if (prefs.get(UserPreferences.preflightEnabled)) return;
  final controller = GetIt.instance<SipflixPreflightController>();
  controller.watchdogFireCount += 1;
  if (controller.watchdogFireCount < 2) return;
  final lastOffer = prefs.get(UserPreferences.preflightLastOfferAt);
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - lastOffer < const Duration(hours: 24).inMilliseconds) return;
  await prefs.set(UserPreferences.preflightLastOfferAt, now);

  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  final enable = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Streaming keeps struggling'),
      content: const Text(
        'Stream Preflight tests your connection before each video and picks '
        'the best route and quality automatically. Turn it on?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  if (enable == true) {
    await prefs.set(UserPreferences.preflightEnabled, true);
  }
}
