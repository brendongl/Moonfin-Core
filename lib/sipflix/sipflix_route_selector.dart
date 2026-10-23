import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../auth/repositories/server_repository.dart';
import '../auth/repositories/session_repository.dart';
import '../data/services/cast/cast_service.dart';
import '../data/services/media_server_client_factory.dart';
import '../preference/user_preferences.dart';
import 'sipflix_bandwidth_probe.dart';
import 'sipflix_connection_manager.dart';
import 'sipflix_servers.dart';

/// An immutable identity snapshot. The token is private app state, never logged.
class SipflixRouteSession {
  const SipflixRouteSession({
    required this.serverId,
    required this.userId,
    required this.token,
    required this.address,
    required this.clientIdentity,
    required this.routes,
  });

  final String serverId;
  final String userId;
  final String token;
  final String address;
  final Object clientIdentity;
  final List<SipflixRouteDef> routes;

  bool sameSession(SipflixRouteSession? other) =>
      other != null &&
      serverId == other.serverId &&
      userId == other.userId &&
      token == other.token &&
      identical(clientIdentity, other.clientIdentity);
}

typedef SipflixRouteProbe = Future<SipflixRouteMeasurement?> Function(
  SipflixRouteDef route,
  String token,
  bool Function() isCancelled,
);

/// Refreshes routes on sign-in, home visits and app resume, without a timer.
/// Each invocation measures every route once, sequentially, up to 10 seconds
/// each. A successful check lasts four hours; failures wait 15 minutes before
/// an event can retry. Playback or session changes cancel the attempt. The
/// independent throughput samples choose the route; no bitrate setting changes.
class SipflixRouteSelector {
  SipflixRouteSelector({
    required SipflixRouteSession? Function() currentSession,
    required bool Function() playbackBusy,
    required SipflixRouteProbe probe,
    required Future<bool> Function(
      SipflixRouteSession session,
      SipflixRouteDef route,
      bool Function() stillCurrent,
    )
    apply,
    DateTime Function()? now,
    this.routeTimeout = const Duration(seconds: 10),
  }) : _currentSession = currentSession,
       _playbackBusy = playbackBusy,
       _probe = probe,
       _apply = apply,
       _now = now ?? DateTime.now;

  static const ttl = Duration(hours: 4);
  static const failureCooldown = Duration(minutes: 15);
  final Duration routeTimeout;
  final SipflixRouteSession? Function() _currentSession;
  final bool Function() _playbackBusy;
  final SipflixRouteProbe _probe;
  final Future<bool> Function(
    SipflixRouteSession,
    SipflixRouteDef,
    bool Function(),
  )
  _apply;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, bool success, String address})> _checks = {};
  final Map<String, ({DateTime at, String address, double mbps})> _health = {};
  Completer<void>? _idle;
  bool _running = false;
  bool _bandwidthMeasurementActive = false;
  int _generation = 0;

  bool get isRunning => _running;

  static String _healthKey(String serverRef) =>
      SipflixServers.defForRef(serverRef)?.recordId ?? serverRef;

  void noteMeasurement(String serverRef, String address, double mbps) {
    if (mbps.isFinite && mbps > 0) {
      _health[_healthKey(serverRef)] = (
        at: _now(),
        address: address,
        mbps: mbps,
      );
    }
  }

  bool needsPreflight(String serverRef, String address, double requiredMbps) {
    final health = _health[_healthKey(serverRef)];
    if (health == null || health.address != address) return true;
    final age = _now().difference(health.at);
    return age.isNegative || age >= ttl || health.mbps < requiredMbps;
  }

  Future<void> cancelAndWait() async {
    cancel();
    await _idle?.future;
  }

  /// Shares the link with the existing Auto bitrate probe. This synchronous
  /// reservation prevents home/resume from starting route probes mid-sample.
  bool beginBandwidthMeasurement() {
    if (_running || _bandwidthMeasurementActive) return false;
    _bandwidthMeasurementActive = true;
    return true;
  }

  void endBandwidthMeasurement() => _bandwidthMeasurementActive = false;

  /// Cancels any in-flight work when the app leaves the foreground.
  void cancel() => _generation++;

  Future<SipflixRouteDef?> refreshIfStale({bool force = false}) async {
    if (_running || _bandwidthMeasurementActive || _playbackBusy()) return null;
    final session = _currentSession();
    // DUMB/Silo has one Jellyfin route: never send it the Emby speed endpoint.
    if (session == null || session.routes.length < 2) return null;
    final key = '${session.serverId}/${session.userId}';
    final last = _checks[key];
    if (!force && last != null && last.address == session.address) {
      final age = _now().difference(last.at);
      if (!age.isNegative && age < (last.success ? ttl : failureCooldown)) {
        return null;
      }
    }
    _running = true;
    _idle = Completer<void>();
    final generation = _generation;
    bool stillCurrent() {
      final current = _currentSession();
      return generation == _generation &&
          !_playbackBusy() &&
          session.sameSession(current) &&
          current!.address == session.address;
    }

    try {
      SipflixRouteDef? best;
      var bestMbps = 0.0;
      for (final route in session.routes) {
        if (!stillCurrent()) return null;
        var timedOut = false;
        SipflixRouteMeasurement? measured;
        try {
          measured =
              await _probe(
                    route,
                    session.token,
                    () => timedOut || !stillCurrent(),
                  )
                  .then<SipflixRouteMeasurement?>(
                    (value) => value,
                    onError: (Object error, StackTrace stack) => null,
                  )
                  .timeout(
                    routeTimeout,
                    onTimeout: () {
                      timedOut = true;
                      return null;
                    },
                  );
        } catch (_) {
          // One unreachable route must not prevent trying the remaining ones.
        }
        if (!stillCurrent()) return null;
        final mbps = measured?.sustainedMbps ?? 0;
        if (!mbps.isFinite || mbps <= 0) continue;
        if (mbps > bestMbps ||
            (mbps == bestMbps && route.url == session.address)) {
          best = route;
          bestMbps = mbps;
        }
      }
      if (!stillCurrent()) return null;
      if (best == null) {
        _checks[key] = (at: _now(), success: false, address: session.address);
        return null;
      }
      if (best.url != session.address &&
          !await _apply(session, best, stillCurrent)) {
        return null;
      }
      final current = _currentSession();
      if (generation != _generation ||
          !session.sameSession(current) ||
          current!.address != best.url)
        return null;
      noteMeasurement(session.serverId, best.url, bestMbps);
      _checks[key] = (at: _now(), success: true, address: best.url);
      return best;
    } catch (_) {
      // Route optimisation is best effort; a working session must stay usable.
      if (stillCurrent()) {
        _checks[key] = (at: _now(), success: false, address: session.address);
      }
      return null;
    } finally {
      _running = false;
      _idle?.complete();
      _idle = null;
    }
  }

  factory SipflixRouteSelector.live() {
    final getIt = GetIt.instance;
    final probe = SipflixBandwidthProbe();
    SipflixRouteSession? current() {
      if (!getIt.isRegistered<SessionRepository>() ||
          !getIt.isRegistered<MediaServerClient>())
        return null;
      final session = getIt<SessionRepository>();
      final client = getIt<MediaServerClient>();
      final serverId = session.activeServerId;
      final userId = session.activeUserId;
      final token = client.accessToken;
      if (serverId == null ||
          userId == null ||
          token == null ||
          token.isEmpty ||
          client.serverType != ServerType.emby)
        return null;
      final def =
          SipflixServers.defForRef(serverId) ??
          SipflixServers.defForRef(client.baseUrl);
      if (def == null || def.routes.length < 2) return null;
      return SipflixRouteSession(
        serverId: serverId,
        userId: userId,
        token: token,
        address: client.baseUrl,
        clientIdentity: client,
        routes: def.routes,
      );
    }

    return SipflixRouteSelector(
      currentSession: current,
      playbackBusy: () {
        if (getIt.isRegistered<CastService>() &&
            getIt<CastService>().activeKind != null)
          return true;
        if (!getIt.isRegistered<PlaybackManager>()) return false;
        final manager = getIt<PlaybackManager>();
        // Paused, queued and resolving sessions count too, not just isPlaying.
        return manager.queueService.currentItem != null ||
            (manager.bringupState.phase != PlaybackBringupPhase.idle &&
                manager.bringupState.phase != PlaybackBringupPhase.failed);
      },
      probe: (route, token, cancelled) => probe.measureRoute(
        baseUrl: route.url,
        accessToken: token,
        isCancelled: cancelled,
      ),
      apply: (session, route, stillCurrent) async {
        final repo = getIt<ServerRepository>();
        final server = repo.getServer(session.serverId);
        if (server == null || !stillCurrent()) return false;
        // A cached bitrate belongs to the old route. Invalidate before changing
        // it; do not touch the viewer's explicit bitrate setting.
        await getIt<UserPreferences>().set(
          UserPreferences.measuredBandwidthAt,
          0,
        );
        return SipflixConnectionManager.applyAutomaticRoute(
          server,
          route,
          repo,
          getIt<MediaServerClientFactory>(),
          stillCurrent: stillCurrent,
        );
      },
    );
  }
}
