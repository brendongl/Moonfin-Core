import 'models/server_type.dart';
import 'models/device_info.dart';
import 'api/auth_api.dart';
import 'api/items_api.dart';
import 'api/playback_api.dart';
import 'api/image_api.dart';
import 'api/session_api.dart';
import 'api/system_api.dart';
import 'api/user_library_api.dart';
import 'api/user_views_api.dart';
import 'api/live_tv_api.dart';
import 'api/instant_mix_api.dart';
import 'api/display_preferences_api.dart';
import 'api/users_api.dart';
import 'api/admin_system_api.dart';
import 'api/admin_users_api.dart';
import 'api/admin_library_api.dart';
import 'api/admin_environment_api.dart';
import 'api/admin_tasks_api.dart';
import 'api/admin_plugins_api.dart';
import 'api/admin_devices_api.dart';
import 'api/admin_api_keys_api.dart';
import 'api/admin_backup_api.dart';
import 'api/admin_live_tv_api.dart';
import 'api/admin_items_api.dart';
import 'api/client_log_api.dart';
import 'api/syncplay_api.dart';
import 'api/games_api.dart';

/// Recovers from a 401 a server's Dio client received for [client]'s active
/// session. Returns true when it refreshed [client.accessToken] and the
/// failed request should be retried once; false when the viewer must sign
/// in again — by then the implementation is expected to have already torn
/// the session down and routed to a sign-in screen. See
/// [UnauthorizedInterceptor].
typedef UnauthorizedHandler = Future<bool> Function(MediaServerClient client);

abstract class MediaServerClient {
  /// Sipflix: wired once at app startup (SessionRepository) so every
  /// server's Dio client funnels a 401 through one recovery path instead of
  /// each call site inventing its own retry/sign-out handling — which is
  /// how a raw `DioException` reached the viewer verbatim (Sipflix swarm
  /// R5/R6 bug B2). Null (e.g. in isolates/tests that never wire it) means
  /// a 401 is simply reported upward unchanged.
  static UnauthorizedHandler? onUnauthorized;

  ServerType get serverType;
  DeviceInfo get deviceInfo;

  String get baseUrl;
  set baseUrl(String url);

  String? get accessToken;
  set accessToken(String? token);

  String? get userId;
  set userId(String? id);

  AuthApi get authApi;
  ItemsApi get itemsApi;
  PlaybackApi get playbackApi;
  ImageApi get imageApi;
  SessionApi get sessionApi;
  SystemApi get systemApi;
  UserLibraryApi get userLibraryApi;
  UserViewsApi get userViewsApi;
  LiveTvApi get liveTvApi;
  InstantMixApi get instantMixApi;
  DisplayPreferencesApi get displayPreferencesApi;
  UsersApi get usersApi;
  AdminSystemApi get adminSystemApi;
  AdminUsersApi get adminUsersApi;
  AdminLibraryApi get adminLibraryApi;
  AdminEnvironmentApi get adminEnvironmentApi;
  AdminTasksApi get adminTasksApi;
  AdminPluginsApi get adminPluginsApi;
  AdminDevicesApi get adminDevicesApi;
  AdminApiKeysApi get adminApiKeysApi;
  AdminBackupApi get adminBackupApi;
  AdminLiveTvApi get adminLiveTvApi;
  AdminItemsApi get adminItemsApi;

  SyncPlayApi? get syncPlayApi => null;



  /// Optional endpoint for uploading client-side diagnostic logs to the server
  /// as reports. Returns null on servers that don't support it (Emby, or
  /// Jellyfin with client log upload disabled).
  ClientLogApi? get clientLogApi => null;

  /// Optional client for the Moonbase plugin retro-games (EmulatorJS) API.
  /// Returns null on servers without the plugin.
  GamesApi? get gamesApi => null;

  void dispose();
}
