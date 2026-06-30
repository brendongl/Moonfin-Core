import '../auth/models/server.dart';
import '../auth/repositories/server_repository.dart';
import '../data/services/media_server_client_factory.dart';
import '../util/server_url.dart';
import 'sipflix_servers.dart';

/// Sipflix: CDN / Direct / VN connection routes for a server.
enum SipflixRoute { cdn, direct, vn }

/// Sipflix: switches a server between its CDN / Direct / VN proxy routes.
///
/// The active route is derived from the server's persisted `address` (which the
/// AuthenticationStore already saves), so no separate state is needed. Switching
/// rewrites the address via [ServerRepository.updateServer] and drops the cached
/// [MediaServerClient] so the next request uses the new endpoint — the clean
/// equivalent of the old Kotlin fork's "soft restart".
class SipflixConnectionManager {
  SipflixConnectionManager._();

  static String label(SipflixRoute route) => switch (route) {
        SipflixRoute.cdn => 'CDN',
        SipflixRoute.direct => 'Direct',
        SipflixRoute.vn => 'VN Proxy',
      };

  static String _url(ServerRoutes r, SipflixRoute route) => switch (route) {
        SipflixRoute.cdn => r.cdn,
        SipflixRoute.direct => r.direct,
        SipflixRoute.vn => r.vn,
      };

  static SipflixRoute _next(SipflixRoute r) => switch (r) {
        SipflixRoute.cdn => SipflixRoute.direct,
        SipflixRoute.direct => SipflixRoute.vn,
        SipflixRoute.vn => SipflixRoute.cdn,
      };

  /// Determine the active route by matching the server's current address
  /// (normalized) against the configured route URLs. Defaults to CDN.
  static SipflixRoute currentRoute(Server server) {
    final routes = SipflixServers.routes[server.id];
    if (routes == null) return SipflixRoute.cdn;
    final addr = normalizeServerBaseUrl(server.address);
    if (addr == normalizeServerBaseUrl(routes.direct)) return SipflixRoute.direct;
    if (addr == normalizeServerBaseUrl(routes.vn)) return SipflixRoute.vn;
    return SipflixRoute.cdn;
  }

  /// Cycle CDN → Direct → VN → CDN. Persists the new address and invalidates
  /// the cached client. Returns the new route (or current if not a Sipflix server).
  static Future<SipflixRoute> toggle(
    Server server,
    ServerRepository serverRepo,
    MediaServerClientFactory clientFactory,
  ) async {
    final routes = SipflixServers.routes[server.id];
    if (routes == null) return currentRoute(server);
    final next = _next(currentRoute(server));
    await serverRepo.updateServer(server.copyWith(address: _url(routes, next)));
    clientFactory.removeClient(server.id);
    return next;
  }
}
