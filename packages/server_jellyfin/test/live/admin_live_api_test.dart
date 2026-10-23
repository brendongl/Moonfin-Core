// Calls the admin APIs against a real Jellyfin server, with write and read
// back round trips, and checks every request against the server's OpenAPI
// document. Skips unless configured:
//
//   MOONFIN_LIVE_URL=<server url> MOONFIN_LIVE_TOKEN=<admin token> \
//   MOONFIN_LIVE_USER_ID=<admin user id> \
//   MOONFIN_OPENAPI=<path to the server's openapi.json> \
//   dart test test/live
//
// MOONFIN_LIVE_READONLY=1 runs only the reads (for a server that must not
// change). Writes put back what they change, but run them on a disposable
// server. MOONFIN_LIVE_LIBRARY_PATHS=a,b names two existing folders for the
// library round trip, empty ones on a server whose media must not be touched.
// MOONFIN_LIVE_SESSION_ITEM is the id of an item playing on a client, for the
// remote control tests. MOONFIN_LIVE_DESTRUCTIVE=1 adds restart, shutdown,
// restore and plugin installs, and MOONFIN_LIVE_CONTAINER names the podman
// container the shutdown test starts again.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:test/test.dart';

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
  late JellyfinMediaServerClient client;

  setUpAll(() {
    if (skipAll != null) return;
    client = JellyfinMediaServerClient(
      baseUrl: url!,
      deviceInfo: const DeviceInfo(
        id: 'moonfin-admin-live-api',
        name: 'Admin live API test',
        appName: 'Moonfin',
        appVersion: 'test',
      ),
      interceptors: [
        InterceptorsWrapper(
          onRequest: (o, h) {
            requests.add((o.method, o.uri.path));
            h.next(o);
          },
        ),
      ],
    )
      ..accessToken = token
      ..userId = userId;
  });

  group('reads', skip: skipAll, () {
    test('server configuration and every named one', () async {
      final config = await client.adminSystemApi.getServerConfiguration();
      expect(config['ServerName'], isA<String>());
      for (final key in [
        'encoding',
        'network',
        'branding',
        'xbmcmetadata',
        'metadata',
        'livetv',
      ]) {
        expect(await client.adminSystemApi.getNamedConfiguration(key), isA<Map>(),
            reason: key);
      }
    });

    test('system lists the pages read', () async {
      final api = client.adminSystemApi;
      expect((await api.getStorageInfo()), isNotNull);
      final logs = await api.getLogFiles();
      expect(logs, isNotEmpty);
      expect(await api.getLogFileContent(logs.first.name), isNotEmpty);
      final activity = await api.getActivityLog(limit: 5, hasUserId: false);
      expect(activity.totalRecordCount, greaterThanOrEqualTo(0));
      expect(await api.getCultures(), isNotEmpty);
      expect(await api.getCountries(), isNotEmpty);
      expect(await api.getLocalizationOptions(), isNotEmpty);
      expect(await api.getParentalRatings(), isNotEmpty);
      expect(await api.getAuthProviders(), isNotEmpty);
      expect(await api.getPasswordResetProviders(), isNotEmpty);
      expect(await api.getItemCounts(), contains('MovieCount'));
    });

    test('users, libraries, tasks, plugins, devices, keys', () async {
      final users = await client.adminUsersApi.getUsers();
      expect(users, isNotEmpty);
      final me = await client.adminUsersApi.getUserById(userId!);
      expect(me.policy, isNotNull);
      await client.adminUsersApi.getChannels();

      final folders = await client.adminLibraryApi.getVirtualFolders();
      expect(folders, isNotEmpty);
      final media = await client.adminLibraryApi.getMediaFolders(isHidden: false);
      expect(media.map((m) => m.itemId), everyElement(isNotEmpty));
      expect(
        await client.adminLibraryApi.getAvailableLibraryOptions('movies'),
        contains('TypeOptions'),
      );

      final tasks = await client.adminTasksApi.getTasks(isHidden: false);
      expect(tasks, isNotEmpty);
      expect(await client.adminTasksApi.getTask(tasks.first['Id'] as String),
          contains('Triggers'));

      expect(await client.adminPluginsApi.getInstalledPlugins(), isNotEmpty);
      expect(await client.adminPluginsApi.getAvailablePackages(), isNotEmpty);
      expect(await client.adminPluginsApi.getRepositories(), isNotEmpty);
      await client.adminPluginsApi.getConfigurationPages();

      expect(await client.adminDevicesApi.getDevices(), isNotEmpty);
      expect(await client.adminApiKeysApi.getApiKeys(), contains('Items'));
      await client.adminBackupApi.getBackups();
    });

    test('folder browser calls', () async {
      final api = client.adminEnvironmentApi;
      expect(await api.getDrives(), isNotEmpty);
      // A library's own folder, so any server's layout works.
      final folder = (await client.adminLibraryApi.getVirtualFolders())
          .expand((f) => f.locations)
          .first;
      final parent = folder.substring(0, folder.lastIndexOf('/'));
      final contents = await api.getDirectoryContents(
        parent,
        includeDirectories: true,
        includeFiles: false,
      );
      expect(contents.map((e) => e['Name']), contains(folder.split('/').last));
      expect(await api.getParentPath(folder), parent);
      await api.validatePath(folder);
      await expectLater(
        api.validatePath('$parent/does-not-exist'),
        throwsA(isA<DioException>()),
      );
    });

    test('live TV reads', () async {
      final api = client.adminLiveTvApi;
      expect(await api.getTunerHostTypes(), isNotEmpty);
      expect(await api.getTunerHosts(), isNotEmpty);
      final providers = await api.getListingProviders();
      expect(providers, isNotEmpty);
      expect(await api.getDefaultListingProvider(), isA<Map>());
      final options = await api.getChannelMappingOptions(
        providers.first['Id'] as String,
      );
      expect(options['TunerChannels'], isNotEmpty);
      expect(await api.getLiveTvConfiguration(), contains('TunerHosts'));
    });
  });

  group('writes', skip: skipWrites, () {
    test('a server configuration save keeps every key', () async {
      final api = client.adminSystemApi;
      final before = await api.getServerConfiguration();
      await api.updateServerConfiguration({
        ...before,
        'ServerName': '${before['ServerName']}-x',
      });
      final after = await api.getServerConfiguration();
      expect(after['ServerName'], '${before['ServerName']}-x');
      await api.updateServerConfiguration(before);
      expect((await api.getServerConfiguration())['ServerName'],
          before['ServerName']);
    });

    test('every named configuration saves and reads back', () async {
      final api = client.adminSystemApi;
      for (final key in ['encoding', 'network', 'branding', 'xbmcmetadata', 'metadata']) {
        final before = await api.getNamedConfiguration(key);
        await api.updateNamedConfiguration(key, before);
        final after = await api.getNamedConfiguration(key);
        expect(after.keys.toSet(), before.keys.toSet(), reason: key);
      }
      final branding = await api.getNamedConfiguration('branding');
      await api.updateNamedConfiguration('branding', {
        ...branding,
        'LoginDisclaimer': 'live test',
      });
      expect(
        (await api.getNamedConfiguration('branding'))['LoginDisclaimer'],
        'live test',
      );
      await api.updateNamedConfiguration('branding', branding);
    });

    test('a user round trip keeps policy keys and preferences', () async {
      final api = client.adminUsersApi;
      final created = await api.createUser('live-api-user', 'pw1');
      try {
        final id = created.id;
        // A schedule and a tag the editor may not show.
        final policy = Map<String, dynamic>.from(
          (await api.getUserById(id)).policy!.toJson(),
        );
        policy['AccessSchedules'] = [
          {'DayOfWeek': 'Sunday', 'StartHour': 8.0, 'EndHour': 20.0, 'UserId': id},
        ];
        policy['AllowedTags'] = ['kids'];
        await api.updateUserPolicy(id, policy);

        // Save the policy again the way the editor does, from what it read.
        final read = (await api.getUserById(id)).policy!.toJson();
        await api.updateUserPolicy(id, {...read, 'EnableRemoteAccess': false});
        final kept = (await api.getUserById(id)).policy!.toJson();
        expect(kept['AccessSchedules'], hasLength(1));
        expect(kept['AllowedTags'], ['kids']);
        expect(kept['EnableRemoteAccess'], isFalse);

        // Rename with the full DTO keeps the configuration.
        final raw = Map<String, dynamic>.from((await api.getUserById(id)).raw);
        final config = Map<String, dynamic>.from(raw['Configuration'] as Map)
          ..['SubtitleLanguagePreference'] = 'fre';
        await api.updateUser(id, {...raw, 'Configuration': config});
        final renamed = Map<String, dynamic>.from(
          (await api.getUserById(id)).raw,
        );
        await api.updateUser(id, {...renamed, 'Name': 'live-api-user-2'});
        final after = await api.getUserById(id);
        expect(after.name, 'live-api-user-2');
        expect(
          (after.raw['Configuration'] as Map)['SubtitleLanguagePreference'],
          'fre',
        );

        await api.updateUserPassword(id, newPassword: 'pw2');
        await api.updateUserPassword(id, resetPassword: true);
      } finally {
        await api.deleteUser(created.id);
      }
      expect(
        (await api.getUsers()).where((u) => u.id == created.id),
        isEmpty,
      );
    });

    test('a library round trip with a path change', () async {
      final api = client.adminLibraryApi;
      const name = 'Live API Library';
      final [first, second] =
          (env['MOONFIN_LIVE_LIBRARY_PATHS'] ?? '/media/Movies,/media/Shows')
              .split(',');
      await api.addVirtualFolder(
        name: name,
        collectionType: 'movies',
        paths: [first],
        refreshLibrary: false,
      );
      try {
        var folder = (await api.getVirtualFolders()).firstWhere((f) => f.name == name);
        await api.addMediaPath(name, second, refreshLibrary: false);
        folder = (await api.getVirtualFolders()).firstWhere((f) => f.name == name);
        expect(folder.locations, containsAll([first, second]));

        // Options saved from the reloaded folder keep both paths, and a
        // type's ImageOptions in the shape the fetcher settings dialog writes.
        const imageOptions = [
          {'Type': 'Primary', 'Limit': 1, 'MinWidth': 0},
          {'Type': 'Logo', 'Limit': 0, 'MinWidth': 0},
          {'Type': 'Backdrop', 'Limit': 3, 'MinWidth': 1280},
        ];
        final options = Map<String, dynamic>.from(folder.libraryOptions!)
          ..['EnableRealtimeMonitor'] = false
          ..['TypeOptions'] = [
            {'Type': 'Movie', 'ImageOptions': imageOptions},
          ];
        await api.updateLibraryOptions(folder.itemId, options);
        folder = (await api.getVirtualFolders()).firstWhere((f) => f.name == name);
        expect(folder.libraryOptions!['EnableRealtimeMonitor'], isFalse);
        expect(folder.locations, hasLength(2));
        final movie = (folder.libraryOptions!['TypeOptions'] as List)
            .cast<Map>()
            .firstWhere((t) => t['Type'] == 'Movie');
        expect(movie['ImageOptions'], imageOptions);

        await api.removeMediaPath(name, second, refreshLibrary: false);
        await api.renameVirtualFolder(name, '$name 2', refreshLibrary: false);
        expect(
          (await api.getVirtualFolders()).map((f) => f.name),
          contains('$name 2'),
        );
      } finally {
        final names = (await api.getVirtualFolders()).map((f) => f.name);
        for (final n in [name, '$name 2']) {
          if (names.contains(n)) await api.removeVirtualFolder(n);
        }
      }
    });

    test('a metadata edit keeps fields it did not change', () async {
      final items = await client.itemsApi.getItems(
        searchTerm: 'Sintel',
        includeItemTypes: const ['Movie'],
        recursive: true,
        fields: 'ProviderIds,OriginalTitle,Tags',
      );
      final id = ((items['Items'] as List).first as Map)['Id'] as String;
      final before = await client.itemsApi.getItem(id);
      await client.adminItemsApi.getMetadataEditor(id);
      await client.adminItemsApi.updateItem(id, {
        ...before,
        'Tags': ['live-test'],
      });
      final after = await client.itemsApi.getItem(id);
      expect(after['Tags'], ['live-test']);
      expect(after['ProviderIds'], before['ProviderIds']);
      expect(after['Name'], before['Name']);
      await client.adminItemsApi.updateItem(id, before);
      expect((await client.itemsApi.getItem(id))['Tags'], before['Tags']);
    });

    test('task triggers change and come back', () async {
      final api = client.adminTasksApi;
      final tasks = await api.getTasks(isHidden: false);
      final task = tasks.firstWhere((t) => t['Key'] == 'CleanActivityLog');
      final id = task['Id'] as String;
      final triggers = List<Map<String, dynamic>>.from(
        (await api.getTask(id))['Triggers'] as List,
      );
      await api.updateTaskTriggers(id, [
        ...triggers,
        {'Type': 'IntervalTrigger', 'IntervalTicks': 36000000000 * 6},
      ]);
      expect((await api.getTask(id))['Triggers'], hasLength(triggers.length + 1));
      await api.updateTaskTriggers(id, triggers);
      expect((await api.getTask(id))['Triggers'], hasLength(triggers.length));

      await api.startTask(id);
      await api.stopTask(id).catchError((_) {});
    });

    test('repositories save and come back', () async {
      final api = client.adminPluginsApi;
      final before = await api.getRepositories();
      await api.setRepositories([
        ...before,
        const RepositoryInfo(
          name: 'Live test',
          url: 'https://example.invalid/manifest.json',
          enabled: false,
        ),
      ]);
      expect((await api.getRepositories()).map((r) => r.name), contains('Live test'));
      await api.setRepositories(before);
      expect(await api.getRepositories(), hasLength(before.length));
    });

    test('an API key is created and revoked', () async {
      final api = client.adminApiKeysApi;
      await api.createApiKey('moonfin-live-test');
      final keys = (await api.getApiKeys())['Items'] as List;
      final key = keys.cast<Map>().firstWhere((k) => k['AppName'] == 'moonfin-live-test');
      await api.revokeApiKey(key['AccessToken'] as String);
      final left = (await api.getApiKeys())['Items'] as List;
      expect(left.cast<Map>().where((k) => k['AppName'] == 'moonfin-live-test'), isEmpty);
    });

    test('a device is renamed and deleted', () async {
      // A scratch device: the viewer signs in once with its own device id.
      final auth = await Dio(BaseOptions(baseUrl: url!)).post<Map<String, dynamic>>(
        '/Users/AuthenticateByName',
        data: {'Username': 'viewer', 'Pw': 'viewer-pw'},
        options: Options(headers: {
          'Authorization':
              'MediaBrowser Client="LiveTest", Device="Scratch", DeviceId="moonfin-live-scratch", Version="1"',
        }),
      );
      expect(auth.data!['AccessToken'], isNotNull);
      final api = client.adminDevicesApi;
      final device = (await api.getDevices()).firstWhere((d) => d.id == 'moonfin-live-scratch');
      await api.updateDeviceOptions(
        device.id,
        const DeviceOptionsDto(customName: 'Scratch renamed'),
      );
      expect((await api.getDeviceOptions(device.id)).customName, 'Scratch renamed');
      await api.deleteDevice(device.id);
      expect(
        (await api.getDevices()).where((d) => d.id == 'moonfin-live-scratch'),
        isEmpty,
      );
    });

    test('live TV: XMLTV edit keeps mappings, a mapping posts one pair', () async {
      final api = client.adminLiveTvApi;
      final provider = (await api.getListingProviders())
          .firstWhere((p) => p['Type'] == 'xmltv');
      final options = await api.getChannelMappingOptions(provider['Id'] as String);
      final tuner = (options['TunerChannels'] as List).first as Map;
      final providerChannel = (options['ProviderChannels'] as List).last as Map;
      await api.setChannelMapping(
        provider['Id'] as String,
        tuner['Id'] as String,
        providerChannel['Id'] as String,
      );
      final mapped = (await api.getListingProviders())
          .firstWhere((p) => p['Id'] == provider['Id']);
      expect(mapped['ChannelMappings'], isNotEmpty);

      // An edit that merges onto the stored entry keeps the mapping.
      await api.addListingProvider({...mapped, 'EnableAllTuners': true});
      final after = (await api.getListingProviders())
          .firstWhere((p) => p['Id'] == provider['Id']);
      expect(after['ChannelMappings'], mapped['ChannelMappings']);

      // Put the provider back as it was.
      await api.addListingProvider(provider);
    });

    test('live TV: a tuner is added and removed', () async {
      final api = client.adminLiveTvApi;
      final added = await api.addTunerHost({
        'Type': 'm3u',
        'Url': 'http://169.254.1.2:9124/playlist.m3u',
        'FriendlyName': 'Live API tuner',
        'TunerCount': 1,
      });
      expect(added['Id'], isNotNull);
      await api.removeTunerHost(added['Id'] as String);
      expect(
        (await api.getTunerHosts()).where((t) => t['Id'] == added['Id']),
        isEmpty,
      );
    });

    test('a small backup is created and its manifest read', () async {
      final api = client.adminBackupApi;
      final created = await api.createBackup({
        'Metadata': false,
        'Subtitles': false,
        'Trickplay': false,
      });
      final path = created['Path'] as String;
      final manifest = await api.getBackupManifest(path);
      expect(manifest, contains('ServerVersion'));
    });
  });

  // Commands are checked through what the server then reports for the
  // session playing MOONFIN_LIVE_SESSION_ITEM, the way the dashboard reads it.
  final sessionItem = env['MOONFIN_LIVE_SESSION_ITEM'];
  group('remote control', skip: skipWrites ?? (sessionItem == null
      ? 'set MOONFIN_LIVE_SESSION_ITEM to an item playing on a client'
      : null), () {
    Future<Map<String, dynamic>> target() async {
      final sessions = await client.sessionApi.getSessions(
        activeWithinSeconds: 960,
      );
      return sessions.firstWhere(
        (s) => (s['NowPlayingItem'] as Map?)?['Id'] == sessionItem,
      );
    }

    Future<Map<String, dynamic>> waitFor(
      bool Function(Map<String, dynamic> session) done,
    ) async {
      for (var i = 0; i < 20; i++) {
        final s = await target();
        if (done(s)) return s;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return target();
    }

    test('pause, unpause, seek, volume, message and stop reach the player', () async {
      final api = client.sessionApi;
      final id = (await target())['Id'] as String;
      Map? state(Map<String, dynamic> s) => s['PlayState'] as Map?;

      await api.sendPlayStateCommand(id, 'Pause');
      expect(state(await waitFor((s) => state(s)?['IsPaused'] == true))?['IsPaused'],
          isTrue);
      await api.sendPlayStateCommand(id, 'Unpause');
      expect(state(await waitFor((s) => state(s)?['IsPaused'] == false))?['IsPaused'],
          isFalse);

      const seekTo = 600 * 10000000; // 10 minutes in
      await api.sendPlayStateCommand(id, 'Seek', seekPositionTicks: seekTo);
      final seeked = await waitFor(
        (s) => ((state(s)?['PositionTicks'] as num?) ?? 0) >= seekTo,
      );
      expect((state(seeked)?['PositionTicks'] as num?) ?? 0,
          greaterThanOrEqualTo(seekTo));

      await api.sendGeneralCommand(id, 'SetVolume', arguments: {'Volume': '30'});
      expect(state(await waitFor((s) => state(s)?['VolumeLevel'] == 30))?['VolumeLevel'],
          30);

      await api.sendMessage(id, 'Moonfin live test', header: 'Moonfin', timeoutMs: 5000);

      await api.sendPlayStateCommand(id, 'Stop');
      var stopped = false;
      for (var i = 0; i < 20 && !stopped; i++) {
        final sessions = await api.getSessions(activeWithinSeconds: 960);
        stopped = !sessions.any(
          (s) => (s['NowPlayingItem'] as Map?)?['Id'] == sessionItem,
        );
        if (!stopped) await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(stopped, isTrue);
    });
  });

  // Restart, shutdown, restore and plugin installs, only on a disposable
  // server.
  final destructive = env['MOONFIN_LIVE_DESTRUCTIVE'] == '1';
  final container = env['MOONFIN_LIVE_CONTAINER'];
  group('destructive', skip: skipWrites ??
      (destructive ? null : 'set MOONFIN_LIVE_DESTRUCTIVE=1'), () {
    Future<void> waitForServer({bool down = false}) async {
      final probe = Dio(BaseOptions(
        baseUrl: url!,
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
      ));
      for (var i = 0; i < 120; i++) {
        var up = false;
        try {
          final r = await probe.get<Map<String, dynamic>>('/System/Info/Public');
          up = r.data?['Version'] != null;
        } catch (_) {}
        if (up != down) return;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      fail('server never came ${down ? 'down' : 'up'}');
    }

    test('a catalog plugin installs, then uninstalls after a restart', () async {
      final api = client.adminPluginsApi;
      const guid = '771e19d653854cafb35c28a0e865cf63';
      await api.installPackage(
        'Kodi Sync Queue',
        assemblyGuid: guid,
        repositoryUrl: 'https://repo.jellyfin.org/files/plugin/manifest.json',
      );
      PluginInfo? installed;
      for (var i = 0; i < 60 && installed == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        installed = (await api.getInstalledPlugins())
            .where((p) => p.id.replaceAll('-', '') == guid)
            .firstOrNull;
      }
      expect(installed, isNotNull, reason: 'install never showed up');

      await client.adminSystemApi.restartServer();
      await waitForServer(down: true);
      await waitForServer();
      final active = (await api.getInstalledPlugins())
          .firstWhere((p) => p.id.replaceAll('-', '') == guid);
      expect(active.status, PluginStatus.active);

      await api.disablePlugin(active.id, active.version);
      expect(
        (await api.getInstalledPlugins())
            .firstWhere((p) => p.id == active.id)
            .status,
        isNot(PluginStatus.active),
      );
      await api.enablePlugin(active.id, active.version);
      await api.uninstallPlugin(active.id, active.version);
      await client.adminSystemApi.restartServer();
      await waitForServer(down: true);
      await waitForServer();
      expect(
        (await api.getInstalledPlugins())
            .where((p) => p.id.replaceAll('-', '') == guid),
        isEmpty,
      );
    }, timeout: const Timeout(Duration(minutes: 6)));

    test('a backup restores and the server comes back', () async {
      final api = client.adminBackupApi;
      final config = await client.adminSystemApi.getServerConfiguration();
      final created = await api.createBackup({
        'Metadata': false,
        'Subtitles': false,
        'Trickplay': false,
      });
      // A change after the backup that the restore must undo.
      await client.adminSystemApi.updateServerConfiguration({
        ...config,
        'ServerName': 'after-backup',
      });
      await api.restoreBackup(created['Path'] as String);
      await waitForServer(down: true);
      await waitForServer();
      expect(
        (await client.adminSystemApi.getServerConfiguration())['ServerName'],
        config['ServerName'],
      );
    }, timeout: const Timeout(Duration(minutes: 6)));

    test('shutdown stops the server', () async {
      await client.adminSystemApi.shutdownServer();
      await waitForServer(down: true);
      final start = await Process.run('podman', ['start', container!]);
      expect(start.exitCode, 0, reason: '${start.stderr}');
      await waitForServer();
    },
      skip: container == null ? 'set MOONFIN_LIVE_CONTAINER' : null,
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });

  group('requests', skip: skipAll, () {
    test('every request names a route in the OpenAPI document', () {
      final doc = env['MOONFIN_OPENAPI'];
      if (doc == null) {
        markTestSkipped('set MOONFIN_OPENAPI');
        return;
      }
      final paths = (jsonDecode(File(doc).readAsStringSync()) as Map)['paths'] as Map;
      final routes = <(String, RegExp)>[
        for (final entry in paths.entries)
          for (final method in (entry.value as Map).keys)
            (
              '$method'.toUpperCase(),
              RegExp('^${(entry.key as String).replaceAll(RegExp(r'\{[^}]+\}'), '[^/]+')}\$',
                  caseSensitive: false),
            ),
      ];
      // Obsolete routes the server keeps but leaves out of the document: one
      // item by user, and the per-user items query the whole app uses.
      final hidden = [
        RegExp(r'^/Users/[^/]+/Items/[^/]+$'),
        RegExp(r'^/Users/[^/]+/Items$'),
      ];
      final unknown = [
        for (final (method, path) in requests)
          if (!routes.any((r) => r.$1 == method && r.$2.hasMatch(path)) &&
              !hidden.any((h) => h.hasMatch(path)))
            '$method $path',
      ];
      expect(unknown, isEmpty);
    });
  });
}
