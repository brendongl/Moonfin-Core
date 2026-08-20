import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/models/server.dart';
import '../auth/store/authentication_store.dart';
import '../util/server_url.dart';

/// A selectable connection route for the Sipflix server. Every route fronts the
/// SAME AlphaV2 backend (verified: same Emby server Id), so switching between
/// them never changes the account, login, or content — only the network path.
class SipflixRouteDef {
  final String id;     // stable key, e.g. 'cdn1' / 'direct'
  final String label;  // shown on the Server Page toggle, e.g. 'CDN 1'
  final String url;
  const SipflixRouteDef({required this.id, required this.label, required this.url});
}

/// Sipflix: the hardcoded Emby server injected on first launch so customers
/// never see an empty "Add Server" screen.
///
/// Defaults to CDN 1 ([cdnUrl]). The Server Page exposes a toggle to switch
/// between the routes in [routeChoices] (CDN 1 / CDN 2 / Direct);
/// the choice persists and is never overridden after the one-time CDN default
/// migration (see [injectOrMigrate]).
class SipflixServers {
  SipflixServers._();

  /// Hide the "Add Server" button — customers use only the hardcoded server.
  static const bool hideAddServer = true;

  /// Force H.264 video (advertise no HEVC/AV1 to the server) so weak Allwinner
  /// boxes never feed HEVC to the buggy `libOmxVdec` hardware decoder, which
  /// SIGSEGVs and freezes the device. The server transcodes HEVC/AV1 -> H.264.
  static const bool forceH264 = true;

  /// Whether the Server Page connection-route toggle is shown.
  static const bool enableRouteToggle = true;

  static const String serverId = '51901ff1-a001-4000-8000-000000000001';

  /// The three routes to the SAME AlphaV2 origin. Verified 2026-08-20: all
  /// three answer `/emby/System/Info/Public` with ServerName=AlphaV2 and
  /// Id=0ad3808b494044e8ac4706a765eef403, so a switch never changes the
  /// account or the library — only the network path.
  ///
  ///   cdn1   -> 103.107.199.53
  ///   cdn2   -> 77.83.241.35   (Datahorders "Nebula", Singapore pool)
  ///   direct -> 208.99.62.25   (the n2 origin)
  ///
  /// CDN 2 is `nebula.cdn2.d-crypt.io`, NOT the `emby.alphacdn2.sipflix.net`
  /// this file used to guess at: that name resolves to 42.115.215.250 and
  /// refuses connections. The homepage's route detector agrees — it labels
  /// CDN2 off X-Real-IP=77.83.241.35.
  static const String cdnUrl = 'https://emby.alphacdn1.sipflix.net';
  static const String cdn2Url = 'https://nebula.cdn2.d-crypt.io';
  static const String directUrl = 'https://emby.n2.d-crypt.io';

  /// The URL new installs default to (CDN 1).
  static const String serverUrl = cdnUrl;

  static const String _serverVersion = '4.9.5.0';

  /// SharedPreferences flag: the one-time "default new/old installs to CDN 1"
  /// migration has run. After it runs the user's route choice is never touched.
  static const String _routeMigratedKey = 'sipflix_route_migrated_v1';

  /// Ordered routes shown on the Server Page toggle and the player's Server
  /// Route button. First entry is the default for a fresh install.
  static const List<SipflixRouteDef> routeChoices = [
    SipflixRouteDef(id: 'cdn1', label: 'CDN 1', url: cdnUrl),
    SipflixRouteDef(id: 'cdn2', label: 'CDN 2', url: cdn2Url),
    SipflixRouteDef(id: 'direct', label: 'Direct', url: directUrl),
  ];

  static bool isSipflixServer(String id) => id == serverId;

  /// Whether [server] IS the Sipflix server.
  ///
  /// Identity is the id when it matches, and the address otherwise. A record
  /// created any way other than [injectOrMigrate] — an older build, a manual
  /// add before the "Add Server" button was hidden — carries a different id,
  /// and an id-only test then hides every route feature on that box while
  /// leaving no trace of why. The address is the honest test: these URLs front
  /// one Emby server that nothing else in the app talks to.
  static bool isSipflixServerRecord(Server server) =>
      server.id == serverId || isSipflixServerRef(server.address);

  /// The Sipflix server among [servers], by id first and address second.
  static Server? findServer(List<Server> servers) {
    for (final s in servers) {
      if (s.id == serverId) return s;
    }
    for (final s in servers) {
      if (isSipflixServerRef(s.address)) return s;
    }
    return null;
  }

  /// Whether [ref] points at the hardcoded Sipflix server, accepting BOTH forms
  /// a server reference takes in this app.
  ///
  /// Items are not always stamped with the stored server's id: the single
  /// server path builds them with `_serverId ?? _client.baseUrl`, so on a fleet
  /// box — which has exactly one server and never passes an explicit id — an
  /// item's `serverId` is usually the base URL it was fetched from.
  /// [MediaServerClientFactory.getClientIfExists] already copes with that; code
  /// that only compared against [serverId] silently treated our own items as
  /// somebody else's server.
  static bool isSipflixServerRef(String ref) {
    if (ref == serverId) return true;
    if (!ref.contains('://')) return false;
    final normalized = normalizeServerBaseUrl(ref);
    return routeChoices
        .any((r) => normalizeServerBaseUrl(r.url) == normalized);
  }

  /// Inject the hardcoded server on first launch, and (exactly once) repoint any
  /// pre-CDN install to the CDN 1 default. The one-time flag is critical now that
  /// the route toggle exists: after the migration runs we must NEVER auto-change
  /// the address again, or a user who selects Direct would be bounced back to
  /// CDN 1 on the next launch. The saved login/token survives a repoint because
  /// [AuthenticationStore.putServer] preserves the existing `users` key.
  static Future<void> injectOrMigrate(AuthenticationStore store) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = store.getServer(serverId);

    if (existing == null) {
      if (store.getServers().isEmpty) {
        await store.putServer(Server(
          id: serverId,
          name: 'Sipflix',
          address: serverUrl,
          version: _serverVersion,
          serverType: ServerType.emby,
          setupCompleted: true,
          dateAdded: DateTime.now(),
        ));
      }
      // Fresh install is already on the CDN 1 default; lock migration so a later
      // toggle to Direct is honoured.
      await prefs.setBool(_routeMigratedKey, true);
      return;
    }

    if (prefs.getBool(_routeMigratedKey) == true) return; // honour the toggle choice
    await prefs.setBool(_routeMigratedKey, true);
    if (existing.address != serverUrl) {
      await store.putServer(existing.copyWith(address: serverUrl));
    }
  }
}
