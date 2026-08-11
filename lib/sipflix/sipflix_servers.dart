import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/models/server.dart';
import '../auth/store/authentication_store.dart';

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
/// between the routes in [routeChoices] (Direct / CDN 1, and CDN 2 once live);
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

  /// CDN 1 (default) and the direct origin. Add cdn2Url when the second CDN lands.
  static const String cdnUrl = 'https://emby.alphacdn1.sipflix.net';
  static const String directUrl = 'https://emby.n2.d-crypt.io';
  // static const String cdn2Url = 'https://emby.alphacdn2.sipflix.net';

  /// The URL new installs default to (CDN 1).
  static const String serverUrl = cdnUrl;

  static const String _serverVersion = '4.9.5.0';

  /// SharedPreferences flag: the one-time "default new/old installs to CDN 1"
  /// migration has run. After it runs the user's route choice is never touched.
  static const String _routeMigratedKey = 'sipflix_route_migrated_v1';

  /// Ordered routes shown on the Server Page toggle. First entry is the default.
  /// Add CDN 2 here (between CDN 1 and Direct) once [cdn2Url] is live.
  static const List<SipflixRouteDef> routeChoices = [
    SipflixRouteDef(id: 'cdn1', label: 'CDN 1', url: cdnUrl),
    // SipflixRouteDef(id: 'cdn2', label: 'CDN 2', url: cdn2Url),
    SipflixRouteDef(id: 'direct', label: 'Direct', url: directUrl),
  ];

  static bool isSipflixServer(String id) => id == serverId;

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
