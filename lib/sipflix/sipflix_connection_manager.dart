import '../auth/models/server.dart';
import '../auth/repositories/server_repository.dart';
import '../data/services/media_server_client_factory.dart';
import '../util/server_url.dart';
import 'sipflix_servers.dart';

/// Sipflix: switches the server between its connection routes (CDN 1 / Direct,
/// and CDN 2 once live — see [SipflixServers.routeChoices]).
///
/// The active route is derived from the server's persisted `address` (which the
/// AuthenticationStore already saves), so no separate state is needed. Switching
/// rewrites the address via [ServerRepository.updateServer] and drops the cached
/// [MediaServerClient] so the next request uses the new endpoint — the clean
/// equivalent of the old Kotlin fork's "soft restart".
class SipflixConnectionManager {
  SipflixConnectionManager._();

  static String label(SipflixRouteDef route) => route.label;

  /// The route whose URL matches the server's current address (normalized).
  /// Falls back to the first route (CDN 1) when nothing matches.
  static SipflixRouteDef currentRoute(Server server) {
    final addr = normalizeServerBaseUrl(server.address);
    for (final r in SipflixServers.routeChoices) {
      if (normalizeServerBaseUrl(r.url) == addr) return r;
    }
    return SipflixServers.routeChoices.first;
  }

  /// The route after [route] in [SipflixServers.routeChoices], wrapping around.
  static SipflixRouteDef _next(SipflixRouteDef route) {
    final choices = SipflixServers.routeChoices;
    final i = choices.indexWhere((r) => r.id == route.id);
    return choices[(i + 1) % choices.length];
  }

  /// Cycle to the next route. Persists the new address and invalidates the
  /// cached client. Returns the new route (or the current one if not a Sipflix
  /// server, or if there's only a single route to choose from).
  static Future<SipflixRouteDef> toggle(
    Server server,
    ServerRepository serverRepo,
    MediaServerClientFactory clientFactory,
  ) async {
    if (!SipflixServers.isSipflixServer(server.id) ||
        SipflixServers.routeChoices.length < 2) {
      return currentRoute(server);
    }
    final next = _next(currentRoute(server));
    await serverRepo.updateServer(server.copyWith(address: next.url));
    clientFactory.removeClient(server.id);
    return next;
  }
}
