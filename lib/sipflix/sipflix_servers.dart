import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/models/server.dart';
import '../auth/store/authentication_store.dart';
import '../util/server_url.dart';
import 'sipflix_4k_policy.dart';

/// A selectable connection route for a Sipflix server. Every route of one
/// server fronts the SAME backend (verified: same Emby server Id), so switching
/// between them never changes the account, login, or content — only the
/// network path.
class SipflixRouteDef {
  final String id;     // stable key, e.g. 'cdn1' / 'direct'
  final String label;  // shown on the Server Page toggle, e.g. 'CDN 1'
  final String url;
  const SipflixRouteDef({required this.id, required this.label, required this.url});
}

/// One Sipflix Emby server: its customer-facing name, the id of the record the
/// app stores for it, and its routes (first = the default for a new sign-in).
class SipflixServerDef {
  /// Stable key, also the admin tooling's name for it ('AlphaV2', 'emby2',
  /// 'iDuck').
  final String key;

  /// The name customers see. Real names, so they know where they are.
  final String name;

  /// The stored [Server.id]. AlphaV2 keeps the id every existing box already
  /// has, so those boxes stay signed in.
  final String recordId;

  /// Emby's own server Id, as `/System/Info/Public` reports it.
  final String embyServerId;
  final String version;
  final List<SipflixRouteDef> routes;

  const SipflixServerDef({
    required this.key,
    required this.name,
    required this.recordId,
    required this.embyServerId,
    required this.version,
    required this.routes,
  });

  SipflixRouteDef get defaultRoute => routes.first;

  /// The server name the playback-report relay is configured with.
  String get reportKey => key.toLowerCase();

  Server toRecord({String? address}) => Server(
        id: recordId,
        name: name,
        address: address ?? defaultRoute.url,
        version: version,
        serverType: ServerType.emby,
        setupCompleted: true,
        dateAdded: DateTime.now(),
      );
}

/// Sipflix: the hardcoded Emby servers. A box is signed in to exactly one of
/// them at a time, because favourites and watch history live on the server.
///
/// The AlphaV2 record is injected on first launch so customers never see an
/// empty "Add Server" screen; signing in finds which server holds the account
/// (see `SipflixSignIn`) and swaps the stored record for that server's.
class SipflixServers {
  SipflixServers._();

  /// Hide the "Add Server" button — customers use only the hardcoded servers.
  static const bool hideAddServer = true;

  /// Force H.264 video (advertise no HEVC/AV1 to the server) so weak Allwinner
  /// boxes never feed HEVC to the buggy `libOmxVdec` hardware decoder, which
  /// SIGSEGVs and freezes the device. The server transcodes HEVC/AV1 -> H.264.
  /// Boxes with a sound HEVC decoder (Shield, Amlogic, ...) are left alone so
  /// they can direct play 4K.
  static bool get forceH264 => Sipflix4kPolicy.isFragileHevcDecoder;

  /// Whether the Server Page connection-route toggle is shown.
  static const bool enableRouteToggle = true;

  /// The AlphaV2 record id — unchanged since the single-server builds.
  static const String serverId = '51901ff1-a001-4000-8000-000000000001';

  /// AlphaV2's three routes. Verified 2026-08-20: all three answer
  /// `/emby/System/Info/Public` with ServerName=AlphaV2 and
  /// Id=0ad3808b494044e8ac4706a765eef403.
  ///
  ///   cdn1   -> 103.107.199.53
  ///   cdn2   -> 77.83.241.35   (Datahorders "Nebula", Singapore pool)
  ///   direct -> 208.99.62.25   (the n2 origin)
  ///
  /// CDN 2 is `nebula.cdn2.d-crypt.io`, NOT the `emby.alphacdn2.sipflix.net`
  /// this file used to guess at: that name resolves to 42.115.215.250 and
  /// refuses connections.
  static const String cdnUrl = 'https://emby.alphacdn1.sipflix.net';
  static const String cdn2Url = 'https://nebula.cdn2.d-crypt.io';
  static const String directUrl = 'https://emby.n2.d-crypt.io';

  /// The URL new installs default to (AlphaV2 CDN 1).
  static const String serverUrl = cdnUrl;

  static const SipflixServerDef alphaV2 = SipflixServerDef(
    key: 'AlphaV2',
    name: 'AlphaV2',
    recordId: serverId,
    embyServerId: '0ad3808b494044e8ac4706a765eef403',
    version: '4.9.5.0',
    routes: [
      SipflixRouteDef(id: 'cdn1', label: 'CDN 1', url: cdnUrl),
      SipflixRouteDef(id: 'cdn2', label: 'CDN 2', url: cdn2Url),
      SipflixRouteDef(id: 'direct', label: 'Direct', url: directUrl),
    ],
  );

  /// emby2, shown to customers as "Delta" (its Emby ServerName). Direct is the
  /// default: the CDN 2 edge answered in 3-6 s against Direct's 0.7 s when
  /// checked 2026-09-28.
  static const SipflixServerDef delta = SipflixServerDef(
    key: 'emby2',
    name: 'Delta',
    recordId: '51901ff1-a001-4000-8000-000000000002',
    embyServerId: '02582a0dd60c4ec2a5ae8989a2b7a6d9',
    version: '4.9.5.0',
    routes: [
      SipflixRouteDef(
          id: 'direct', label: 'Direct', url: 'https://emby2.n2.d-crypt.io'),
      SipflixRouteDef(
          id: 'cdn2', label: 'CDN 2', url: 'https://emby.cdn2.d-crypt.io'),
    ],
  );

  static const SipflixServerDef iDuck = SipflixServerDef(
    key: 'iDuck',
    name: 'iDuck',
    recordId: '51901ff1-a001-4000-8000-000000000003',
    embyServerId: 'd5a6152afd3246f4bc698df48af54ebc',
    version: '4.9.3.0',
    routes: [
      SipflixRouteDef(
          id: 'cdn', label: 'CDN', url: 'https://34335.brr.savethecdn.com'),
      SipflixRouteDef(
          id: 'direct', label: 'Direct', url: 'http://95.216.4.149:42418'),
    ],
  );

  /// Every server, in the order a picker lists them.
  static const List<SipflixServerDef> all = [alphaV2, delta, iDuck];

  /// The most routes any one server has. Sizes budgets that scale with it.
  static int get maxRouteCount =>
      all.map((d) => d.routes.length).reduce((a, b) => a > b ? a : b);

  /// SharedPreferences flag: the one-time "default new/old installs to CDN 1"
  /// migration has run. After it runs the user's route choice is never touched.
  static const String _routeMigratedKey = 'sipflix_route_migrated_v1';

  /// AlphaV2's routes. Kept for callers that predate multiple servers; code
  /// that has a [Server] in hand should use [routesFor].
  static List<SipflixRouteDef> get routeChoices => alphaV2.routes;

  /// The server [recordId] names, or null.
  static SipflixServerDef? defForId(String recordId) {
    for (final d in all) {
      if (d.recordId == recordId) return d;
    }
    return null;
  }

  /// The server whose record id or route URL [ref] is, or null.
  static SipflixServerDef? defForRef(String ref) {
    final byId = defForId(ref);
    if (byId != null) return byId;
    if (!ref.contains('://')) return null;
    final normalized = normalizeServerBaseUrl(ref);
    for (final d in all) {
      if (d.routes.any((r) => normalizeServerBaseUrl(r.url) == normalized)) {
        return d;
      }
    }
    return null;
  }

  /// The server [server] is a record of, by id first and address second.
  static SipflixServerDef? defForServer(Server server) =>
      defForId(server.id) ?? defForRef(server.address);

  /// The routes of the server [server] is a record of (AlphaV2's when it is
  /// not one of ours, which callers rule out first).
  static List<SipflixRouteDef> routesFor(Server server) =>
      (defForServer(server) ?? alphaV2).routes;

  static bool isSipflixServer(String id) => defForId(id) != null;

  /// Whether [server] IS a Sipflix server.
  ///
  /// Identity is the id when it matches, and the address otherwise. A record
  /// created any way other than [injectOrMigrate] — an older build, a manual
  /// add before the "Add Server" button was hidden — carries a different id,
  /// and an id-only test then hides every route feature on that box while
  /// leaving no trace of why. The address is the honest test: these URLs front
  /// servers that nothing else in the app talks to.
  static bool isSipflixServerRecord(Server server) =>
      defForServer(server) != null;

  /// The Sipflix server among [servers], by id first and address second.
  /// A box holds one at a time; [preferId] breaks a tie if it ever holds more.
  static Server? findServer(List<Server> servers, {String? preferId}) {
    if (preferId != null) {
      for (final s in servers) {
        if (s.id == preferId && isSipflixServerRecord(s)) return s;
      }
    }
    for (final s in servers) {
      if (defForId(s.id) != null) return s;
    }
    for (final s in servers) {
      if (isSipflixServerRef(s.address)) return s;
    }
    return null;
  }

  /// Whether [ref] points at a Sipflix server, accepting BOTH forms a server
  /// reference takes in this app.
  ///
  /// Items are not always stamped with the stored server's id: the single
  /// server path builds them with `_serverId ?? _client.baseUrl`, so on a fleet
  /// box — which has exactly one server and never passes an explicit id — an
  /// item's `serverId` is usually the base URL it was fetched from.
  /// [MediaServerClientFactory.getClientIfExists] already copes with that; code
  /// that only compared against [serverId] silently treated our own items as
  /// somebody else's server. Covers every route of every server, so Delta and
  /// iDuck get route switching and playback reports too.
  static bool isSipflixServerRef(String ref) => defForRef(ref) != null;

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
        await store.putServer(alphaV2.toRecord());
      }
      // Fresh install is already on the CDN 1 default; lock migration so a later
      // toggle to Direct is honoured. A box signed in to Delta or iDuck lands
      // here too, and must be left exactly as it is.
      await prefs.setBool(_routeMigratedKey, true);
      return;
    }

    // Single-server builds named the record "Sipflix". Show the real name.
    if (existing.name != alphaV2.name) {
      await store.putServer(existing.copyWith(name: alphaV2.name));
    }

    if (prefs.getBool(_routeMigratedKey) == true) return; // honour the toggle choice
    await prefs.setBool(_routeMigratedKey, true);
    if (existing.address != serverUrl) {
      final current = store.getServer(serverId) ?? existing;
      await store.putServer(current.copyWith(address: serverUrl));
    }
  }
}
