import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../auth/models/server.dart';
import '../auth/repositories/server_repository.dart';
import '../data/services/media_server_client_factory.dart';
import '../util/server_url.dart';
import 'sipflix_servers.dart';

/// Sipflix: switches a server between its connection routes (AlphaV2's
/// CDN 1 / CDN 2 / Direct, Delta's Direct / CDN 2, ... — see
/// [SipflixServers.routesFor]).
///
/// The active route is derived from the server's persisted `address` (which the
/// AuthenticationStore already saves), so no separate state is needed.
///
/// Switching retargets the LIVE clients in place ([MediaServerClient.baseUrl]),
/// which is what actually moves traffic. Persisting the address alone only
/// takes effect at the next sign-in, because the signed-in app keeps using the
/// `MediaServerClient` singleton that [setActiveServerClient] registered at
/// login — that stale singleton is why a mid-session switch used to look like
/// it had done nothing. The Emby client's `baseUrl` setter rewrites its Dio
/// base and its playback API reads the field through a closure, so a retarget
/// moves both the REST calls and the stream URLs. Stream Preflight has applied
/// the winning route this way since it shipped; this is the same mechanism.
class SipflixConnectionManager {
  SipflixConnectionManager._();

  static String label(SipflixRouteDef route) => route.label;

  /// The route whose URL matches the server's current address (normalized).
  /// Falls back to the server's first route when nothing matches.
  static SipflixRouteDef currentRoute(Server server) {
    final routes = SipflixServers.routesFor(server);
    final addr = normalizeServerBaseUrl(server.address);
    for (final r in routes) {
      if (normalizeServerBaseUrl(r.url) == addr) return r;
    }
    return routes.first;
  }

  /// The route after [route] among [server]'s routes, wrapping around.
  /// Public so the UI can name what a switch would land on.
  static SipflixRouteDef nextRoute(Server server, SipflixRouteDef route) {
    final choices = SipflixServers.routesFor(server);
    final i = choices.indexWhere((r) => r.id == route.id);
    return choices[(i + 1) % choices.length];
  }

  /// Switch [server] to [route]: persist the address and retarget every live
  /// client for it, so the change applies to the session already running
  /// instead of waiting for the next launch.
  ///
  /// Deliberately does NOT evict the cached client. Eviction disposes a client
  /// the signed-in session is still holding, and the replacement is built
  /// without the access token, so the retarget-in-place above is both gentler
  /// and more complete.
  static Future<void> applyRoute(
    Server server,
    SipflixRouteDef route,
    ServerRepository serverRepo,
    MediaServerClientFactory clientFactory,
  ) async {
    await serverRepo.updateServer(server.copyWith(address: route.url));

    _retargetClients(server, route, clientFactory);
  }

  /// Automatic selection rechecks ownership immediately before synchronously
  /// retargeting. No await separates that check from the live-client update,
  /// so playback starting during disk persistence already uses the new route.
  static Future<bool> applyAutomaticRoute(
    Server server,
    SipflixRouteDef route,
    ServerRepository serverRepo,
    MediaServerClientFactory clientFactory, {
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) return false;
    _retargetClients(server, route, clientFactory);
    await serverRepo.updateServer(server.copyWith(address: route.url));
    return true;
  }

  static void _retargetClients(
    Server server,
    SipflixRouteDef route,
    MediaServerClientFactory clientFactory,
  ) {
    // The factory's client and the registered singleton are two wrappers over
    // the same raw client, so this is belt and braces — but the singleton is
    // registered before some screens ever ask the factory, and missing either
    // one is exactly the failure this method exists to stop.
    clientFactory.getClientIfExists(server.id)?.baseUrl = route.url;

    final getIt = GetIt.instance;
    if (getIt.isRegistered<MediaServerClient>()) {
      final active = getIt<MediaServerClient>();
      // Only retarget the singleton when it is this server's client; on a
      // multi-server install it could belong to somebody else entirely.
      final activeAddr = normalizeServerBaseUrl(active.baseUrl);
      final isThisServer = SipflixServers.routesFor(server)
          .any((r) => normalizeServerBaseUrl(r.url) == activeAddr);
      if (isThisServer) active.baseUrl = route.url;
    }
  }

  /// Cycle to the next route. Returns the new route (or the current one if not
  /// a Sipflix server, or if there's only a single route to choose from).
  static Future<SipflixRouteDef> toggle(
    Server server,
    ServerRepository serverRepo,
    MediaServerClientFactory clientFactory,
  ) async {
    if (!SipflixServers.isSipflixServerRecord(server) ||
        SipflixServers.routesFor(server).length < 2) {
      return currentRoute(server);
    }
    final next = nextRoute(server, currentRoute(server));
    await applyRoute(server, next, serverRepo, clientFactory);
    return next;
  }
}
