// Calls the Emby admin APIs against a real Emby server, with write and read
// back round trips, and checks every request against the server's OpenAPI
// document. Skips unless configured:
//
//   MOONFIN_LIVE_URL=<server url, with /emby> MOONFIN_LIVE_TOKEN=<admin token> \
//   MOONFIN_LIVE_USER_ID=<admin user id> \
//   MOONFIN_OPENAPI=<path to the server's openapi.json> \
//   dart test test/live
//
// MOONFIN_LIVE_READONLY=1 runs only the reads (for a server that must not
// change). Writes put back what they change, but run them on a disposable
// server. MOONFIN_LIVE_LIBRARY_PATHS=a,b names two existing folders for the
// library round trip, empty ones on a server whose media must not be touched.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:server_emby/src/api/emby_admin_api_keys_api.dart';
import 'package:server_emby/src/api/emby_admin_devices_api.dart';
import 'package:server_emby/src/api/emby_admin_environment_api.dart';
import 'package:server_emby/src/api/emby_admin_items_api.dart';
import 'package:server_emby/src/api/emby_admin_library_api.dart';
import 'package:server_emby/src/api/emby_admin_system_api.dart';
import 'package:server_emby/src/api/emby_admin_tasks_api.dart';
import 'package:server_emby/src/api/emby_admin_users_api.dart';
import 'package:test/test.dart';

const _auth =
    'Emby Client="Moonfin", Device="Admin live API test", '
    'DeviceId="moonfin-admin-live-api", Version="test"';

void main() {
  final env = Platform.environment;
  final url = env['MOONFIN_LIVE_URL'];
  final token = env['MOONFIN_LIVE_TOKEN'];
  final userId = env['MOONFIN_LIVE_USER_ID'];
  final readOnly = env['MOONFIN_LIVE_READONLY'] == '1';
  final skipAll = url == null || token == null || userId == null
      ? 'set MOONFIN_LIVE_URL, MOONFIN_LIVE_TOKEN and MOONFIN_LIVE_USER_ID'
      : null;
  final skipWrites = skipAll ?? (readOnly ? 'read only run' : null);

  final requests = <(String, String)>{};
  late Dio dio;
  late EmbyAdminSystemApi system;
  late EmbyAdminUsersApi users;
  late EmbyAdminLibraryApi library;
  late EmbyAdminEnvironmentApi environment;
  late EmbyAdminTasksApi tasks;
  late EmbyAdminDevicesApi devices;
  late EmbyAdminApiKeysApi keys;
  late EmbyAdminItemsApi items;

  setUpAll(() {
    if (skipAll != null) return;
    final basePath = Uri.parse(url!).path;
    dio = Dio(
      BaseOptions(
        baseUrl: url,
        headers: {'Authorization': '$_auth, Token="$token"'},
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add((o.method, o.uri.path.substring(basePath.length)));
          if (readOnly && o.method != 'GET') {
            return h.reject(
              DioException(requestOptions: o, error: 'read only'),
            );
          }
          h.next(o);
        },
      ),
    );
    system = EmbyAdminSystemApi(dio);
    users = EmbyAdminUsersApi(dio);
    library = EmbyAdminLibraryApi(dio);
    environment = EmbyAdminEnvironmentApi(dio);
    tasks = EmbyAdminTasksApi(dio);
    devices = EmbyAdminDevicesApi(dio);
    keys = EmbyAdminApiKeysApi(dio);
    items = EmbyAdminItemsApi(dio);
  });

  const namedKeys = [
    'encoding',
    'branding',
    'xbmcmetadata',
    'metadata',
    'devices',
    'sync',
    'dlna',
    'cinemamode',
  ];

  /// A movie the metadata tests can read and edit.
  Future<String> anyMovie() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/Users/$userId/Items',
      queryParameters: {
        'Recursive': true,
        'IncludeItemTypes': 'Movie',
        'Limit': 1,
      },
    );
    return ((response.data!['Items'] as List).first as Map)['Id'] as String;
  }

  Future<Map<String, dynamic>> getItem(String id) async =>
      (await dio.get<Map<String, dynamic>>('/Users/$userId/Items/$id')).data!;

  group('reads', skip: skipAll, () {
    test('server configuration and every named one', () async {
      expect(await system.getServerConfiguration(), contains('UICulture'));
      for (final key in [...namedKeys, 'livetv']) {
        expect(
          await system.getNamedConfiguration(key),
          isA<Map>(),
          reason: key,
        );
      }
    });

    test('system pages read', () async {
      final storage = await system.getStorageInfo();
      expect(storage.programDataPath, isNotEmpty);
      expect(storage.logPath, isNotEmpty);
      final logs = await system.getLogFiles();
      expect(logs, isNotEmpty);
      expect(await system.getLogFileContent(logs.first.name), isNotEmpty);

      final activity = await system.getActivityLog(limit: 5, hasUserId: false);
      expect(activity.items.length, lessThanOrEqualTo(5));
      expect(activity.items.map((e) => e.userId), everyElement(isNull));
      final all = await system.getActivityLog(limit: 1);
      if (all.items.isNotEmpty) {
        final newest = all.items.first.date;
        final since = await system.getActivityLog(minDate: newest);
        expect(since.items, isNotEmpty);
        expect(
          since.items.map((e) => e.date.isBefore(newest)),
          everyElement(isFalse),
        );
      }

      expect(await system.getCultures(), isNotEmpty);
      expect(await system.getCountries(), isNotEmpty);
      expect(await system.getLocalizationOptions(), isNotEmpty);
      expect(await system.getParentalRatings(), isNotEmpty);
      expect(await system.getAuthProviders(), isNotEmpty);
      expect(await system.getPasswordResetProviders(), isEmpty);
      expect(await system.getItemCounts(), contains('MovieCount'));
    });

    test('users, libraries, tasks, devices, keys', () async {
      expect(await users.getUsers(), isNotEmpty);
      expect(
        await users.getUsers(isDisabled: false, isHidden: false),
        isNotEmpty,
      );
      final me = await users.getUserById(userId!);
      expect(me.policy?.isAdministrator, isTrue);
      await users.getChannels();
      await users.getChannels(supportsMediaDeletion: true);

      final folders = await library.getVirtualFolders();
      expect(folders, isNotEmpty);
      expect(folders.map((f) => f.itemId), everyElement(isNotEmpty));
      final media = await library.getMediaFolders(isHidden: false);
      expect(media, isNotEmpty);
      expect(media.map((m) => m.itemId), everyElement(isNotEmpty));
      expect(folders.map((f) => f.name), containsAll(media.map((m) => m.name)));
      expect(await library.getPhysicalPaths(), isNotEmpty);
      expect(
        await library.getAvailableLibraryOptions('movies'),
        contains('TypeOptions'),
      );

      final list = await tasks.getTasks(isHidden: false);
      expect(list, isNotEmpty);
      expect(
        await tasks.getTask(list.first['Id'] as String),
        contains('Triggers'),
      );

      final all = await devices.getDevices();
      expect(all, isNotEmpty);
      final device = all.first;
      expect((await devices.getDeviceInfo(device.id)).id, device.id);
      await devices.getDeviceOptions(device.id);
      expect(
        (await devices.getDevices(userId: device.lastUserId)).map((d) => d.id),
        contains(device.id),
      );

      expect(await keys.getApiKeys(), contains('Items'));
    });

    test('folder browser calls', () async {
      expect(await environment.getDrives(), isNotEmpty);
      // The server's own log folder, so any layout works and the server can
      // always read it.
      final folder = (await system.getStorageInfo()).logPath;
      final parent = folder.substring(0, folder.lastIndexOf('/'));
      final contents = await environment.getDirectoryContents(
        parent,
        includeDirectories: true,
        includeFiles: false,
      );
      expect(contents.map((e) => e['Name']), contains(folder.split('/').last));
      expect(await environment.getParentPath(folder), parent);
    });

    test('metadata reads', () async {
      final id = await anyMovie();
      expect(await items.getMetadataEditor(id), contains('ExternalIdInfos'));
      expect(await items.getExternalIdInfos(id), isNotEmpty);
      expect(
        await items.getRemoteImages(id, imageType: ImageType.primary, limit: 2),
        contains('Images'),
      );
    });
  });

  group('writes', skip: skipWrites, () {
    test('a server configuration save keeps every key', () async {
      final before = await system.getServerConfiguration();
      await system.updateServerConfiguration({
        ...before,
        'ServerName': 'live-test-name',
      });
      final after = await system.getServerConfiguration();
      expect(after['ServerName'], 'live-test-name');
      expect(after.keys, containsAll(before.keys));
      // An unset name is left out of the read, and only an explicit null
      // clears it again.
      await system.updateServerConfiguration({
        ...before,
        'ServerName': before['ServerName'],
      });
      expect(await system.getServerConfiguration(), before);
    });

    test('every named configuration saves and reads back', () async {
      for (final key in namedKeys) {
        final before = await system.getNamedConfiguration(key);
        await system.updateNamedConfiguration(key, before);
        expect(await system.getNamedConfiguration(key), before, reason: key);
      }
      final branding = await system.getNamedConfiguration('branding');
      await system.updateNamedConfiguration('branding', {
        ...branding,
        'LoginDisclaimer': 'live test',
      });
      expect(
        (await system.getNamedConfiguration('branding'))['LoginDisclaimer'],
        'live test',
      );
      await system.updateNamedConfiguration('branding', branding);
      expect(await system.getNamedConfiguration('branding'), branding);
    });

    test('path validation', () async {
      final storage = await system.getStorageInfo();
      final folder = storage.logPath;
      await environment.validatePath(folder);
      await expectLater(
        environment.validatePath(folder, isFile: true),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        environment.validatePath('$folder/does-not-exist'),
        throwsA(isA<DioException>()),
      );
      // The cache folder is always the server's to write.
      await environment.validatePath(storage.cachePath, writable: true);
    });

    test('a user round trip keeps policy keys and preferences', () async {
      final created = await users.createUser('live-api-user', 'pw1');
      try {
        final id = created.id;
        expect(created.hasPassword, isTrue);
        // A schedule and a tag the editor may not show.
        final policy = Map<String, dynamic>.from(
          (await users.getUserById(id)).policy!.toJson(),
        );
        policy['AccessSchedules'] = [
          {'DayOfWeek': 'Sunday', 'StartHour': 8.0, 'EndHour': 20.0},
        ];
        policy['BlockedTags'] = ['kids'];
        await users.updateUserPolicy(id, policy);

        // Save the policy again the way the editor does, from what it read.
        final read = (await users.getUserById(id)).policy!.toJson();
        await users.updateUserPolicy(id, {
          ...read,
          'EnableRemoteAccess': false,
        });
        final kept = (await users.getUserById(id)).policy!.toJson();
        expect(kept['AccessSchedules'], hasLength(1));
        expect(kept['BlockedTags'], ['kids']);
        expect(kept['EnableRemoteAccess'], isFalse);

        // Library access is saved by the folder ids getMediaFolders gives.
        final folder = (await library.getMediaFolders(isHidden: false)).first;
        await users.updateUserPolicy(id, {
          ...kept,
          'EnableAllFolders': false,
          'EnabledFolders': [folder.itemId],
        });
        final views =
            (await dio.get<Map<String, dynamic>>(
                  '/Users/$id/Views',
                )).data!['Items']
                as List;
        expect(views.map((v) => (v as Map)['Name']), contains(folder.name));

        // Rename with the full DTO keeps the configuration.
        final raw = Map<String, dynamic>.from(
          (await users.getUserById(id)).raw,
        );
        final config = Map<String, dynamic>.from(raw['Configuration'] as Map)
          ..['SubtitleLanguagePreference'] = 'fre';
        await users.updateUser(id, {...raw, 'Configuration': config});
        final renamed = Map<String, dynamic>.from(
          (await users.getUserById(id)).raw,
        );
        await users.updateUser(id, {...renamed, 'Name': 'live-api-user-2'});
        final after = await users.getUserById(id);
        expect(after.name, 'live-api-user-2');
        expect(
          (after.raw['Configuration'] as Map)['SubtitleLanguagePreference'],
          'fre',
        );

        await users.updateUserPassword(
          id,
          currentPassword: 'pw1',
          newPassword: 'pw2',
        );
        await users.updateUserPassword(id, resetPassword: true);
        expect((await users.getUserById(id)).hasPassword, isFalse);
      } finally {
        await users.deleteUser(created.id);
      }
      expect(
        (await users.getUsers()).where((u) => u.id == created.id),
        isEmpty,
      );
    });

    test('a library round trip with a path change', () async {
      const name = 'Live API Library';
      final [
        first,
        second,
      ] = (env['MOONFIN_LIVE_LIBRARY_PATHS'] ?? '/media/Movies,/media/Shows')
          .split(',');
      await library.addVirtualFolder(
        name: name,
        collectionType: 'movies',
        paths: [first],
        libraryOptions: {'EnableRealtimeMonitor': false},
      );
      Future<VirtualFolderInfo?> find(String n) async =>
          (await library.getVirtualFolders())
              .where((f) => f.name == n)
              .firstOrNull;
      try {
        var folder = (await find(name))!;
        final id = folder.itemId;
        await library.addMediaPath(name, second, libraryId: id);
        folder = (await find(name))!;
        expect(folder.locations, containsAll([first, second]));

        await library.updateMediaPath(name, {
          'Path': second,
          'NetworkPath': 'smb://nas/live',
        }, libraryId: id);
        folder = (await find(name))!;
        final pathInfos = (folder.libraryOptions!['PathInfos'] as List)
            .cast<Map>();
        expect(
          pathInfos.firstWhere((p) => p['Path'] == second)['NetworkPath'],
          'smb://nas/live',
        );

        // Options saved from the reloaded folder keep both paths, and a
        // type's ImageOptions in the shape the fetcher settings dialog writes.
        const imageOptions = [
          {'Type': 'Primary', 'Limit': 1, 'MinWidth': 0},
          {'Type': 'Backdrop', 'Limit': 3, 'MinWidth': 1280},
        ];
        final options = Map<String, dynamic>.from(folder.libraryOptions!)
          ..['EnableRealtimeMonitor'] = true
          ..['TypeOptions'] = [
            {'Type': 'Movie', 'ImageOptions': imageOptions},
          ];
        await library.updateLibraryOptions(id, options);
        folder = (await find(name))!;
        expect(folder.libraryOptions!['EnableRealtimeMonitor'], isTrue);
        expect(folder.locations, hasLength(2));
        final movie = (folder.libraryOptions!['TypeOptions'] as List)
            .cast<Map>()
            .firstWhere((t) => t['Type'] == 'Movie');
        expect(movie['ImageOptions'], imageOptions);

        await library.removeMediaPath(name, second, libraryId: id);
        expect((await find(name))!.locations, [first]);
        await library.renameVirtualFolder(name, '$name 2', libraryId: id);
        expect(await find('$name 2'), isNotNull);
      } finally {
        for (final n in [name, '$name 2']) {
          final f = await find(n);
          if (f != null) {
            await library.removeVirtualFolder(n, libraryId: f.itemId);
          }
        }
      }
      expect(await find('$name 2'), isNull);
    });

    test("a metadata edit keeps fields it didn't change", () async {
      final id = await anyMovie();
      final before = await getItem(id);
      // Emby's tags are TagItems, Tags is ignored.
      await items.updateItem(id, {
        ...before,
        'TagItems': [
          {'Name': 'live-test'},
        ],
      });
      final after = await getItem(id);
      expect((after['TagItems'] as List).map((t) => (t as Map)['Name']), [
        'live-test',
      ]);
      expect(after['ProviderIds'], before['ProviderIds']);
      expect(after['Name'], before['Name']);
      await items.updateItem(id, before);
      expect((await getItem(id))['TagItems'], before['TagItems']);
    });

    test('an image is added and removed by index', () async {
      final id = await anyMovie();
      List<dynamic> backdrops(Map<String, dynamic> item) =>
          item['BackdropImageTags'] as List? ?? const [];
      final before = backdrops(await getItem(id));
      await items.uploadItemImage(
        id,
        imageType: ImageType.backdrop,
        bytes: _png,
        contentType: 'image/png',
      );
      expect(backdrops(await getItem(id)), hasLength(before.length + 1));
      await items.deleteItemImage(
        id,
        imageType: ImageType.backdrop,
        imageIndex: before.length,
      );
      expect(backdrops(await getItem(id)), before);
    });

    test('refresh and remote search run', () async {
      final id = await anyMovie();
      await items.refreshItem(id);
      final item = await getItem(id);
      final results = await items.searchRemote('movie', {
        'SearchInfo': {'Name': item['Name']},
        'ItemId': id,
        'IncludeDisabledProviders': true,
      });
      expect(results, isA<List>());
      expect(
        () => items.updateContentType(id, 'movies'),
        throwsUnsupportedError,
      );
    });

    test('task triggers change and come back', () async {
      final task = (await tasks.getTasks(
        isHidden: false,
      )).firstWhere((t) => t['Key'] == 'VacuumDatabase');
      final id = task['Id'] as String;
      final triggers = List<Map<String, dynamic>>.from(
        (await tasks.getTask(id))['Triggers'] as List,
      );
      await tasks.updateTaskTriggers(id, [
        ...triggers,
        {'Type': 'IntervalTrigger', 'IntervalTicks': 36000000000 * 6},
      ]);
      expect(
        (await tasks.getTask(id))['Triggers'],
        hasLength(triggers.length + 1),
      );
      await tasks.updateTaskTriggers(id, triggers);
      expect((await tasks.getTask(id))['Triggers'], triggers);

      await tasks.startTask(id);
      await tasks.stopTask(id).catchError((_) {});
    });

    test('an API key is created and revoked', () async {
      await keys.createApiKey('moonfin-live-test');
      final list = (await keys.getApiKeys())['Items'] as List;
      final key = list.cast<Map>().firstWhere(
        (k) => k['AppName'] == 'moonfin-live-test',
      );
      await keys.revokeApiKey(key['AccessToken'] as String);
      final left = (await keys.getApiKeys())['Items'] as List;
      expect(
        left.cast<Map>().where((k) => k['AppName'] == 'moonfin-live-test'),
        isEmpty,
      );
    });

    test('a device is renamed and deleted', () async {
      // A scratch device: a scratch user signs in once with its own device id.
      final user = await users.createUser('live-api-device-user', 'pw');
      try {
        await Dio(BaseOptions(baseUrl: url!)).post<Map<String, dynamic>>(
          '/Users/AuthenticateByName',
          data: {'Username': 'live-api-device-user', 'Pw': 'pw'},
          options: Options(
            headers: {
              'Authorization':
                  'Emby Client="LiveTest", Device="Scratch", DeviceId="moonfin-live-scratch", Version="1"',
            },
          ),
        );
        bool isScratch(DeviceInfoDto d) =>
            d.reportedDeviceId == 'moonfin-live-scratch';
        final device = (await devices.getDevices(
          userId: user.id,
        )).firstWhere(isScratch);
        await devices.updateDeviceOptions(
          device.id,
          const DeviceOptionsDto(customName: 'Scratch renamed'),
        );
        expect(
          (await devices.getDeviceOptions(device.id)).customName,
          'Scratch renamed',
        );
        expect(
          (await devices.getDeviceInfo(device.id)).displayName,
          'Scratch renamed',
        );
        await devices.deleteDevice(device.id);
        expect((await devices.getDevices()).where(isScratch), isEmpty);
      } finally {
        await users.deleteUser(user.id);
      }
    });
  });

  group('requests', skip: skipAll, () {
    test('every request names a route in the OpenAPI document', () {
      final doc = env['MOONFIN_OPENAPI'];
      if (doc == null) {
        markTestSkipped('set MOONFIN_OPENAPI');
        return;
      }
      final paths =
          (jsonDecode(File(doc).readAsStringSync()) as Map)['paths'] as Map;
      final routes = <(String, RegExp)>[
        for (final entry in paths.entries)
          for (final method in (entry.value as Map).keys)
            (
              '$method'.toUpperCase(),
              RegExp(
                '^${(entry.key as String).replaceAll(RegExp(r'\{[^}]+\}'), '[^/]+')}\$',
                caseSensitive: false,
              ),
            ),
      ];
      final unknown = [
        for (final (method, path) in requests)
          if (!routes.any((r) => r.$1 == method && r.$2.hasMatch(path)))
            '$method $path',
      ];
      expect(unknown, isEmpty);
    });
  });
}

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);
