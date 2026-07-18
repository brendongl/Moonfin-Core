import 'package:server_core/server_core.dart';

import '../auth/models/server.dart';
import '../auth/store/authentication_store.dart';

/// Sipflix: the hardcoded Emby server injected on first launch so customers
/// never see an empty "Add Server" screen.
///
/// Currently a single server (`emby.n2.d-crypt.io`) with no CDN, so the
/// CDN/Direct/VN route toggle is disabled ([enableRouteToggle] = false). The
/// route plumbing (all three routes point at the one URL) is kept dormant so a
/// CDN/proxy can be reintroduced later by flipping the flag and adding routes.
class SipflixServers {
  SipflixServers._();

  /// Hide the "Add Server" button — customers use only the hardcoded server.
  static const bool hideAddServer = true;

  /// Force H.264 video (advertise no HEVC/AV1 to the server) so weak Allwinner
  /// boxes never feed HEVC to the buggy `libOmxVdec` hardware decoder, which
  /// SIGSEGVs and freezes the device. The server transcodes HEVC/AV1 -> H.264.
  static const bool forceH264 = true;

  /// Whether the CDN/Direct/VN connection toggle is shown. Off while there's a
  /// single URL (no CDN); flip on and populate [routes] to re-enable it.
  static const bool enableRouteToggle = false;

  static const String serverId = '51901ff1-a001-4000-8000-000000000001';
  static const String serverUrl = 'https://emby.n2.d-crypt.io';

  /// Routes per server. Single URL for now — all three point at the one server.
  static const Map<String, ServerRoutes> routes = {
    serverId: ServerRoutes(cdn: serverUrl, direct: serverUrl, vn: serverUrl),
  };

  static bool isSipflixServer(String id) => routes.containsKey(id);

  /// Inject the hardcoded Emby server on first launch if none exist.
  static Future<void> injectIfEmpty(AuthenticationStore store) async {
    if (store.getServers().isNotEmpty) return;
    await store.putServer(Server(
      id: serverId,
      name: 'Sipflix',
      address: serverUrl,
      version: '4.10.0.4',
      serverType: ServerType.emby,
      setupCompleted: true,
      dateAdded: DateTime.now(),
    ));
  }
}

/// The connection routes available for a Sipflix server (dormant while there's
/// a single URL — see [SipflixServers.enableRouteToggle]).
class ServerRoutes {
  final String cdn;
  final String direct;
  final String vn;
  const ServerRoutes({required this.cdn, required this.direct, required this.vn});
}
