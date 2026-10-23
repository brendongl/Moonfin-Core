import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:server_core/server_core.dart';

import 'api/emby_admin_api_keys_api.dart';
import 'api/emby_admin_devices_api.dart';
import 'api/emby_admin_environment_api.dart';
import 'api/emby_admin_extras_api.dart';
import 'api/emby_admin_items_api.dart';
import 'api/emby_admin_library_api.dart';
import 'api/emby_admin_live_tv_api.dart';
import 'api/emby_admin_plugins_api.dart';
import 'api/emby_admin_system_api.dart';
import 'api/emby_admin_tasks_api.dart';
import 'api/emby_admin_users_api.dart';
import 'api/emby_auth_api.dart';
import 'api/emby_client_log_api.dart';
import 'api/emby_items_api.dart';
import 'api/emby_playback_api.dart';
import 'api/emby_image_api.dart';
import 'api/emby_session_api.dart';
import 'api/emby_system_api.dart';
import 'api/emby_user_library_api.dart';
import 'api/emby_user_views_api.dart';
import 'api/emby_live_tv_api.dart';
import 'api/emby_instant_mix_api.dart';
import 'api/emby_display_preferences_api.dart';
import 'api/emby_users_api.dart';
import 'api/emby_trickplay_api.dart';

class EmbyMediaServerClient extends MediaServerClient {
  final Dio _dio;
  final Logger _logger = Logger();

  static bool Function() hideStandalone4k = () => false;

  static final _listPath = RegExp(
    r'^/(Items|Users/[^/]+/Items|Users/[^/]+/Items/(Resume|Latest)|Shows/NextUp)$',
  );

  // Every list-shaped response that can carry Movie/Episode children. This is
  // deliberately wider than [_listPath]: it also covers paths Emby's own
  // Is4K filter can't be applied to at request time (mixed Movie+Series
  // results with no IncludeItemTypes — Home rows, Favorites, Studio pages,
  // Collections) and one path [_listPath] doesn't match at all
  // (Shows/{id}/Episodes), so those get a response-side post-filter instead.
  static final _postFilterPath = RegExp(
    r'^/(Items|Users/[^/]+/Items|Users/[^/]+/Items/(Resume|Latest)|'
    r'Shows/NextUp|Shows/[^/]+/Episodes)$',
  );

  // How many ids go into one 4K-survivor probe per page. Keeps the query
  // string bounded even for a large page size.
  static const int _uhdProbeBatchSize = 150;

  @override
  final DeviceInfo deviceInfo;

  /// [interceptors] run after the client's own, so a test or a diagnostics
  /// harness sees each request as sent, auth header included.
  EmbyMediaServerClient({
    required String baseUrl,
    required this.deviceInfo,
    List<Interceptor> interceptors = const [],
  }) : _dio = Dio(BaseOptions(
         baseUrl: baseUrl,
         followRedirects: false,
         // Only the connect. Waiting for a free slot happens before this
         // starts, so it can stay short enough to give up on a hung host.
         connectTimeout: const Duration(seconds: 8),
         receiveTimeout: const Duration(minutes: 3),
       )) {
    _baseUrl = baseUrl;
    configureServerDio(_dio);
    _setupInterceptors();
    _dio.interceptors.addAll(interceptors);
  }

  late String _baseUrl;
  String? _accessToken;
  String? _userId;

  // Progress goes out every five seconds and would fill the report inside an
  // hour, so only one answer a minute is kept. A ping that fails still goes
  // through onError.
  static const _progressPingLogInterval = 12;
  int _progressPings = 0;

  bool _isProgressPing(Uri uri) =>
      uri.path.endsWith('/Sessions/Playing/Progress');

  bool _progressPingIsDue() {
    _progressPings++;
    return _progressPings % _progressPingLogInterval == 1;
  }

  void _setupInterceptors() {
    _dio.interceptors.add(UnauthorizedInterceptor(
      _dio,
      onUnauthorized: () async {
        final handler = MediaServerClient.onUnauthorized;
        if (handler == null) return false;
        return handler(this);
      },
    ));
    _dio.interceptors.add(redirectInterceptor(_dio));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'GET' &&
            hideStandalone4k() &&
            _listPath.hasMatch(options.path) &&
            !options.queryParameters.containsKey('Ids') &&
            !options.queryParameters.containsKey('Is4K') &&
            _carries4kFlag(options.path, options.queryParameters)) {
          options.queryParameters['Is4K'] = false;
        }
        options.headers['Authorization'] = buildServerAuthorizationHeader(
          scheme: 'Emby',
          deviceInfo: deviceInfo,
          accessToken: _accessToken,
        );
        if (!_isProgressPing(options.uri)) {
          ServerLog.network('→ ${options.method} ${options.uri}');
        }
        handler.next(options);
      },
      // Sipflix fork: 4K post-filter runs first, then upstream's logging.
      onResponse: (response, handler) async {
        final path = response.requestOptions.path;
        final query = response.requestOptions.queryParameters;
        // Resume/Latest/NextUp silently ignore the Is4K param server-side
        // (confirmed against Delta: Is4K=true and Is4K=false return the same
        // Resume items) — unlike a plain typed /Items query, which does
        // honour it. So those three paths are post-filtered unconditionally;
        // everywhere else, an Is4K already on the request (added above, or
        // passed explicitly) means the response is already correctly
        // scoped and the extra probe would be wasted.
        // Favorites (IsFavorite=true) is in the same boat: a typed Movie/
        // Episode favorites query gets Is4K=false added at request time
        // (via _carries4kFlag above) same as any other typed list, but on
        // Delta a 4K-only favorited item ("Pompeii: Disaster Street",
        // 3549673) still came back anyway — Is4K isn't honoured once
        // IsFavorite is also on the request, the same silent-ignore shape
        // already known for Resume/Latest/NextUp. Trusting the request-time
        // Is4K here meant this path skipped the post-filter below entirely
        // (query already "has" Is4K, so the server was assumed to have done
        // the job) and the leak went straight through.
        final isFavoriteQuery = query['IsFavorite'] == true ||
            query['IsFavorite']?.toString().toLowerCase() == 'true';
        final isUnreliableIs4kEndpoint =
            RegExp(r'/(Resume|Latest)$|^/Shows/NextUp$').hasMatch(path) ||
            isFavoriteQuery;
        if (response.requestOptions.method == 'GET' &&
            hideStandalone4k() &&
            _postFilterPath.hasMatch(path) &&
            // The probe itself (and any explicit Ids-based lookup) must
            // bypass this filter, or every probe would spawn another probe.
            !query.containsKey('Ids') &&
            (isUnreliableIs4kEndpoint || !query.containsKey('Is4K'))) {
          try {
            await _postFilterUhd(response);
          } catch (e, st) {
            // Fail open: an unfilterable page still shows its items rather
            // than going blank, but gets logged so it's not silent.
            _logger.w('4K post-filter probe failed, showing items unfiltered',
                error: e, stackTrace: st);
          }
        }
        final uri = response.requestOptions.uri;
        if (!_isProgressPing(uri) || _progressPingIsDue()) {
          ServerLog.network(
            '← ${response.statusCode} ${response.requestOptions.method} $uri',
          );
        }
        handler.next(response);
      },
      onError: (error, handler) {
        ServerLog.network(
          '✗ ${error.requestOptions.method} ${error.requestOptions.uri} '
          '(${error.response?.statusCode ?? error.type.name})',
          level: ServerLogLevel.error,
          error: error.message ?? error.toString(),
        );
        handler.next(error);
      },
    ));
  }

  /// Drops Movie/Episode items this fragile-decoder box can't play from a
  /// list-shaped response, in place. Series/BoxSet/Folder/Person/etc. items
  /// are left untouched — Emby's Is4K filter (and this probe) only means
  /// anything for the types that carry the flag.
  ///
  /// One typed follow-up query per page (`Ids=<page's Movie/Episode ids>&
  /// Is4K=false`) decides which of those ids have a playable version; this
  /// is the same probe shape already used for collections (2f2c69f6b).
  ///
  /// A hidden 4K-only episode leaves a gap in its season's episode numbers
  /// rather than being silently renumbered — consistent with the existing
  /// collections behaviour (2f2c69f6b), which likewise drops items in place.
  Future<void> _postFilterUhd(Response response) async {
    final data = response.data;
    // /Items/Latest returns a bare JSON array; every other matched path
    // returns {Items: [...], TotalRecordCount: n}.
    final isBareList = data is List;
    final rawItems = isBareList
        ? data
        : (data is Map ? data['Items'] : null);
    if (rawItems is! List || rawItems.isEmpty) return;

    final items = rawItems.whereType<Map>().toList();
    final candidateIds = <String>[];
    for (final item in items) {
      final type = item['Type']?.toString();
      if (type == 'Movie' || type == 'Episode') {
        final id = item['Id']?.toString();
        if (id != null) candidateIds.add(id);
      }
    }
    if (candidateIds.isEmpty) return;

    final survivors = <String>{};
    for (var i = 0; i < candidateIds.length; i += _uhdProbeBatchSize) {
      final end = i + _uhdProbeBatchSize;
      final batch = candidateIds.sublist(
        i,
        end < candidateIds.length ? end : candidateIds.length,
      );
      final probe = await _dio.get(
        '/Users/${_requireUserId()}/Items',
        queryParameters: {
          'Ids': batch.join(','),
          'IncludeItemTypes': 'Movie,Episode',
          'Is4K': false,
          'Fields': '',
          'Limit': batch.length,
        },
      );
      final probeData = probe.data;
      final probeItems = probeData is Map ? probeData['Items'] : null;
      if (probeItems is List) {
        survivors.addAll(probeItems
            .whereType<Map>()
            .map((m) => m['Id']?.toString())
            .whereType<String>());
      }
    }

    final blockedCount = items
        .where((item) =>
            (item['Type'] == 'Movie' || item['Type'] == 'Episode') &&
            !survivors.contains(item['Id']?.toString()))
        .length;
    if (blockedCount == 0) return;

    final filtered = rawItems.where((raw) {
      if (raw is! Map) return true;
      final type = raw['Type']?.toString();
      if (type != 'Movie' && type != 'Episode') return true;
      return survivors.contains(raw['Id']?.toString());
    }).toList();

    if (isBareList) {
      response.data = filtered;
    } else {
      final map = data as Map;
      map['Items'] = filtered;
      // Best-effort: this page's items shrank, so walk the reported total
      // down by the same amount. It can't be made exact (the server's own
      // count still includes 4K-only items on pages this probe hasn't seen
      // yet), but undercounting slightly is harmless — a consumer that
      // pages until it stops getting full pages, or until it reaches the
      // (now slightly high) total, still terminates; it just does one extra
      // page request in the worst case rather than stopping early.
      final total = map['TotalRecordCount'];
      if (total is int) {
        map['TotalRecordCount'] = total - blockedCount;
      }
    }
  }

  String _requireUserId() {
    final id = _userId;
    if (id == null) throw StateError('userId not configured');
    return id;
  }

  // Emby's Is4K=false matches nothing for Series/BoxSet, so only add it when
  // the query is limited to types that carry the flag (or is Resume/Latest/NextUp).
  static bool _carries4kFlag(String path, Map<String, dynamic> query) {
    if (RegExp(r'/(Resume|Latest)$|^/Shows/NextUp$').hasMatch(path)) return true;
    final types = query['IncludeItemTypes'];
    if (types == null) return false;
    final list = (types is Iterable ? types : types.toString().split(','))
        .map((t) => t.toString().trim())
        .where((t) => t.isNotEmpty);
    if (list.isEmpty) return false;
    return list.every(
      (t) => const {'Movie', 'Episode', 'Video', 'MusicVideo'}.contains(t),
    );
  }

  @override
  ServerType get serverType => ServerType.emby;

  @override
  String get baseUrl => _baseUrl;

  @override
  set baseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
  }

  @override
  String? get accessToken => _accessToken;

  @override
  set accessToken(String? token) => _accessToken = token;

  @override
  String? get userId => _userId;

  @override
  set userId(String? id) => _userId = id;

  @override
  late final AuthApi authApi = EmbyAuthApi(_dio);

  @override
  late final ItemsApi itemsApi = EmbyItemsApi(_dio, _requireUserId);

  @override
  late final PlaybackApi playbackApi =
      EmbyPlaybackApi(_dio, () => _baseUrl);

  @override
  late final ImageApi imageApi =
      EmbyImageApi(() => _baseUrl, () => _accessToken);

  @override
  late final TrickplayApi trickplayApi =
      EmbyTrickplayApi(_dio, () => _baseUrl, () => _accessToken);

  @override
  late final SessionApi sessionApi = EmbySessionApi(_dio);

  @override
  late final SystemApi systemApi = EmbySystemApi(_dio);

  @override
  late final UserLibraryApi userLibraryApi =
      EmbyUserLibraryApi(_dio, _requireUserId);

  @override
  late final EmbyUserViewsApi userViewsApi =
      EmbyUserViewsApi(_dio, _requireUserId, () => usersApi);

  @override
  late final LiveTvApi liveTvApi = EmbyLiveTvApi(_dio);

  @override
  late final InstantMixApi instantMixApi = EmbyInstantMixApi(_dio);

  @override
  late final EmbyDisplayPreferencesApi displayPreferencesApi =
      EmbyDisplayPreferencesApi(_dio);

  @override
  late final UsersApi usersApi = EmbyUsersApi(
    _dio,
    _requireUserId,
    onConfigurationUpdated: () => userViewsApi.invalidateCache(),
  );

  @override
  late final ClientLogApi clientLogApi = EmbyClientLogApi(_dio);

  @override
  late final AdminSystemApi adminSystemApi = EmbyAdminSystemApi(_dio);

  @override
  late final AdminUsersApi adminUsersApi = EmbyAdminUsersApi(_dio);

  @override
  late final AdminLibraryApi adminLibraryApi = EmbyAdminLibraryApi(_dio);

  @override
  late final AdminEnvironmentApi adminEnvironmentApi = EmbyAdminEnvironmentApi(_dio);

  @override
  late final AdminTasksApi adminTasksApi = EmbyAdminTasksApi(_dio);

  @override
  late final AdminPluginsApi adminPluginsApi = EmbyAdminPluginsApi(_dio);

  @override
  late final AdminDevicesApi adminDevicesApi = EmbyAdminDevicesApi(_dio);

  @override
  late final AdminApiKeysApi adminApiKeysApi = EmbyAdminApiKeysApi(_dio);

  /// Emby's backups come from a plugin, through [embyAdminApi].
  @override
  AdminBackupApi get adminBackupApi =>
      throw UnsupportedError('Emby has no built-in backups');

  @override
  late final EmbyAdminApi embyAdminApi = EmbyAdminExtrasApi(_dio);

  @override
  late final AdminLiveTvApi adminLiveTvApi = EmbyAdminLiveTvApi(_dio);

  @override
  late final AdminItemsApi adminItemsApi = EmbyAdminItemsApi(_dio);

  @override
  late final GamesApi gamesApi = MoonbaseGamesApi(
      _dio, () => _baseUrl, () => _accessToken, ServerType.emby);

  @override
  void dispose() {
    _dio.close();
  }
}
