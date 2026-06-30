import 'package:server_core/server_core.dart';

import '../auth/models/server.dart';
import '../auth/store/authentication_store.dart';

/// Sipflix: hardcoded Emby servers + CDN/Direct/VN route definitions.
///
/// Ported from the old Kotlin fork (`SipflixServerInjector` +
/// `SipflixConnectionManager`). The two servers are injected on first launch
/// so customers never see an empty "Add Server" screen, and each carries three
/// switchable routes (CDN / Direct / VN proxy).
class SipflixServers {
  SipflixServers._();

  /// Hide the "Add Server" button — customers use only the hardcoded servers.
  static const bool hideAddServer = true;

  /// Force H.264 video (advertise no HEVC/AV1 to the server) so these weak
  /// Allwinner boxes never feed HEVC to the buggy `libOmxVdec` hardware decoder,
  /// which SIGSEGVs and freezes the device. The server transcodes HEVC/AV1 -> H264.
  static const bool forceH264 = true;

  // Fixed IDs for stable identification across launches (match old Kotlin fork).
  static const String alphaId = '51901ff1-a001-4000-8000-000000000001';
  static const String iduckId = '51901ff1-a001-4000-8000-000000000002';

  /// CDN / Direct / VN routes per server. The injected default is the CDN route.
  static const Map<String, ServerRoutes> routes = {
    alphaId: ServerRoutes(
      cdn: 'https://emby.alphacdn.sipflix.net',
      direct: 'https://emby.alpha.sipflix.net',
      vn: 'https://emby.alphavn.sipflix.net',
    ),
    iduckId: ServerRoutes(
      cdn: 'https://34335.brr.savethecdn.com',
      direct: 'http://95.216.4.149:42418',
      vn: 'https://emby.iduckvn.sipflix.net',
    ),
  };

  static bool isSipflixServer(String serverId) => routes.containsKey(serverId);

  /// Inject the hardcoded Emby servers on first launch if none exist.
  static Future<void> injectIfEmpty(AuthenticationStore store) async {
    if (store.getServers().isNotEmpty) return;
    final now = DateTime.now();
    await store.putServer(Server(
      id: alphaId,
      name: 'Alpha',
      address: routes[alphaId]!.cdn,
      version: '4.10.0.4',
      serverType: ServerType.emby,
      setupCompleted: true,
      dateAdded: now,
    ));
    await store.putServer(Server(
      id: iduckId,
      name: 'iDuck',
      address: routes[iduckId]!.cdn,
      version: '4.10.0.4',
      serverType: ServerType.emby,
      setupCompleted: true,
      dateAdded: now,
    ));
  }
}

/// The three connection routes available for a Sipflix server.
class ServerRoutes {
  final String cdn;
  final String direct;
  final String vn;
  const ServerRoutes({required this.cdn, required this.direct, required this.vn});
}
