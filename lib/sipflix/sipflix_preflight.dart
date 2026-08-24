import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import 'sipflix_log.dart';
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
        _logger = logger ?? sipflixLogger();

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

  /// Per-route probe ceiling, mirroring `measureRoute`'s own timeout.
  static const Duration perRouteCap = Duration(seconds: 10);

  /// Verdict hold + UI, on top of the probes.
  static const Duration _verdictSlack = Duration(seconds: 6);

  /// The whole preflight (UI + every probe + apply) is capped here; timeout is
  /// pure fail-open insurance ("play normally"), never the normal path.
  ///
  /// DERIVED from the route count, not a constant. It used to be a hardcoded
  /// 26s sized for two routes; adding CDN 2 made the worst case 3 x 10s + hold
  /// = ~31s, so a slow first route ate the budget and the LAST route in the
  /// list — Direct — was never probed before the whole preflight timed out and
  /// fell open. Probes run sequentially on purpose (parallel ones would share
  /// the link and each read a fraction of the truth), so this has to grow with
  /// the list.
  static Duration get overallTimeout =>
      perRouteCap * SipflixServers.routeChoices.length + _verdictSlack;

  /// Watchdog fires this session (for the enable-offer prompt).
  int watchdogFireCount = 0;

  bool _running = false;

  /// Live handles so the overall timeout can wind the check down immediately
  /// (cancel the in-flight probe + pull the overlay) instead of leaving it to
  /// finish and linger over the video that has already started.
  SipflixPreflightProgress? _activeProgress;
  _PreflightOverlay? _activePage;

  /// The [PlaybackManager.preflightHook] entry point.
  Future<PlaybackPreflightResult?> runForItem(dynamic item) async {
    final prefs = GetIt.instance<UserPreferences>();
    if (!prefs.get(UserPreferences.preflightEnabled)) return null;
    return runFor(item);
  }

  /// Run the check for [item] regardless of the per-play setting.
  ///
  /// This is the on-demand entry point: the player's Stream Check button and
  /// the "playback is struggling" offer both land here. Gating every play was
  /// the wrong default — it taxes every start to fix the minority that
  /// stutter — so the check is now something a struggling stream asks for.
  Future<PlaybackPreflightResult?> runFor(dynamic item) async {
    if (_running) return null;
    if (item is! AggregatedItem) return null;
    if (!_eligibleTypes.contains(item.type)) return null;
    if (item.rawData['__moonfinIsPreroll'] == true) return null;
    if (!SipflixServers.isSipflixServerRef(item.serverId)) return null;
    if (!GetIt.instance<ConnectivityService>().isOnline) return null;

    _running = true;
    try {
      return await _run(item).timeout(overallTimeout, onTimeout: () {
        _logger.w('Sipflix preflight timed out — playing normally');
        _activeProgress?.abort();
        _activePage?.close();
        return null;
      });
    } catch (e) {
      _logger.w('Sipflix preflight failed: $e');
      return null;
    } finally {
      _activeProgress = null;
      _activePage = null;
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
    _activeProgress = progress;

    // Render as an OverlayEntry, NOT a pushed route. showDialog pushes a
    // pageless route onto go_router's own navigator; popping it makes go_router
    // rebuild its page list, which disposes the /video-player page underneath
    // (its dispose() calls manager.stop(), bumping the session token and making
    // the in-flight resolve stale — playback silently never starts). An overlay
    // entry floats above every page, is invisible to go_router, and removing it
    // pops no route and disposes no page.
    final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
    _PreflightOverlay? page;
    if (navContext != null && navContext.mounted) {
      final overlay = Overlay.maybeOf(navContext, rootOverlay: true);
      if (overlay != null) {
        page = _PreflightOverlay(progress: progress);
        page.insertInto(overlay);
        _activePage = page;
      }
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
      final server = SipflixServers.findServer(serverRepo.servers);
      if (server != null &&
          SipflixConnectionManager.currentRoute(server).id !=
              decision.route.id) {
        await SipflixConnectionManager.applyRoute(
          server,
          decision.route,
          serverRepo,
          factory,
        );
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
      await Future<void>.delayed(const Duration(milliseconds: 1400));
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

  /// Completed steps, newest last — the page shows these verbatim so the
  /// customer can follow exactly what the check is doing.
  final List<String> log = [];

  /// The step running right now (rendered with a spinner), or null.
  String? activeStep;

  SipflixPreflightProgress({
    required this.itemName,
    required this.requiredMbps,
    required this.routes,
  }) {
    log.add('Preflight started');
    log.add(
      'This video needs ~${requiredMbps.toStringAsFixed(0)} Mbps '
      'for full quality',
    );
  }

  void markTesting(String routeId) {
    testingRouteId = routeId;
    final label = _labelOf(routeId);
    activeStep = 'Testing $label…';
    notifyListeners();
  }

  void markResult(String routeId, SipflixRouteMeasurement m) {
    results[routeId] = m;
    testingRouteId = null;
    activeStep = null;
    log.add(
      '${_labelOf(routeId)}: ${m.sustainedMbps.toStringAsFixed(1)} Mbps '
      'sustained, ${m.burstMbps.toStringAsFixed(0)} burst',
    );
    notifyListeners();
  }

  void markFailed(String routeId) {
    results[routeId] = null;
    testingRouteId = null;
    activeStep = null;
    log.add('${_labelOf(routeId)}: not reachable');
    notifyListeners();
  }

  void markDecision(SipflixPreflightDecision d) {
    decision = d;
    activeStep = null;
    log.add(
      d.direct
          ? 'Route chosen: ${d.route.label} — full quality'
          : 'Route chosen: ${d.route.label} — capped at ${d.capMbps} Mbps',
    );
    notifyListeners();
  }

  void abort() {
    aborted = true;
    notifyListeners();
  }

  String _labelOf(String routeId) =>
      routes.where((r) => r.id == routeId).firstOrNull?.label ?? routeId;
}

/// Owns the full-screen preflight UI as an OverlayEntry (see the note in
/// [SipflixPreflightController._run] for why this is an overlay and not a
/// route). [close] removes the entry; it is idempotent so the controller's
/// finally and a user skip can both call it safely.
class _PreflightOverlay {
  _PreflightOverlay({required this.progress});

  final SipflixPreflightProgress progress;
  OverlayEntry? _entry;

  void insertInto(OverlayState overlay) {
    _entry = OverlayEntry(
      builder: (_) => _PreflightView(progress: progress, onClose: close),
    );
    overlay.insert(_entry!);
  }

  void close() {
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
    }
  }
}

/// Full-screen preflight view. OK short-press skips this one check; holding OK
/// for [_holdToDisable] turns the feature off entirely (operator spec); Back
/// skips. [onClose] removes the owning overlay entry.
class _PreflightView extends StatefulWidget {
  final SipflixPreflightProgress progress;
  final VoidCallback onClose;

  const _PreflightView({required this.progress, required this.onClose});

  @override
  State<_PreflightView> createState() => _PreflightViewState();
}

class _PreflightViewState extends State<_PreflightView> {
  static const _holdToDisable = Duration(milliseconds: 1200);
  DateTime? _selectDownAt;
  bool _closed = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'sipflixPreflight');

  @override
  void initState() {
    super.initState();
    // Grab DPAD focus off the (still-mounted) player screen underneath.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onClose();
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
    _focusNode.dispose();
    super.dispose();
  }

  String? _verdictLine() {
    final d = widget.progress.decision;
    if (d == null) return null;
    if (d.direct) return 'Full quality on ${d.route.label}';
    return '${d.route.label} at ${d.capMbps} Mbps for smooth playback';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FocusScope(
        autofocus: true,
        child: Focus(
          focusNode: _focusNode,
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
                        errorBuilder: (_, _, _) => const Icon(
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
                      for (final step in widget.progress.log)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '\u2713  $step',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      if (widget.progress.activeStep != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.progress.activeStep!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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
        ),
      ),
    );
  }
}

/// Offer, at most once a day, to run the check on the stream that is
/// struggling right now.
///
/// It used to offer to switch Stream Preflight ON — a permanent gate before
/// every future play — which is a large commitment to ask for in the middle of
/// a bad stream, and taxes every good one afterwards. Running it once, here, on
/// the thing that is actually stuttering, is the smaller and more useful offer.
/// Returns the result when the customer accepted and the check produced one.
Future<PlaybackPreflightResult?> maybeOfferPreflight({dynamic item}) async {
  final prefs = GetIt.instance<UserPreferences>();
  final controller = GetIt.instance<SipflixPreflightController>();
  // Already gating every play: nothing to offer.
  if (prefs.get(UserPreferences.preflightEnabled)) return null;
  controller.watchdogFireCount += 1;
  if (controller.watchdogFireCount < 2) return null;
  final lastOffer = prefs.get(UserPreferences.preflightLastOfferAt);
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - lastOffer < const Duration(hours: 24).inMilliseconds) return null;
  await prefs.set(UserPreferences.preflightLastOfferAt, now);

  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  if (context == null || !context.mounted) return null;
  final run = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Playback keeps struggling'),
      content: const Text(
        'Run stream diagnostics? It tests each connection route and picks the '
        'best one for this video. Takes about ten seconds.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Run diagnostics'),
        ),
      ],
    ),
  );
  if (run != true || item == null) return null;
  return controller.runFor(item);
}
