// Calls the Emby plugin, Live TV and Emby-only admin APIs against a real
// server, with write and read back round trips, and checks every request
// against the server's OpenAPI document. Skips unless configured:
//
//   MOONFIN_LIVE_URL=<server url ending in /emby> \
//   MOONFIN_LIVE_TOKEN=<admin token> MOONFIN_LIVE_USER_ID=<admin user id> \
//   MOONFIN_OPENAPI=<path to the server's openapi.json> \
//   dart test test/live/admin_extras_live_api_test.dart
//
// MOONFIN_LIVE_READONLY=1 runs only the reads (for a server that must not
// change). Writes put back what they change, but run them on a disposable
// server. MOONFIN_LIVE_M3U is a playlist URL the server can fetch, for the
// tuner round trip, since Emby won't save a tuner it can't reach.
// MOONFIN_LIVE_DESTRUCTIVE=1 adds a plugin install and uninstall, which
// restart the server twice.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:server_emby/src/api/emby_admin_extras_api.dart';
import 'package:server_emby/src/api/emby_admin_live_tv_api.dart';
import 'package:server_emby/src/api/emby_admin_plugins_api.dart';
import 'package:test/test.dart';

const _backupPluginId = 'e711475e-efad-431b-8527-033ba9873a34';

void main() {
  final env = Platform.environment;
  final url = env['MOONFIN_LIVE_URL'];
  final token = env['MOONFIN_LIVE_TOKEN'];
  final userId = env['MOONFIN_LIVE_USER_ID'];
  final readOnly = env['MOONFIN_LIVE_READONLY'] == '1';
  final m3u = env['MOONFIN_LIVE_M3U'];
  final skipAll = url == null || token == null || userId == null
      ? 'set MOONFIN_LIVE_URL, MOONFIN_LIVE_TOKEN and MOONFIN_LIVE_USER_ID'
      : null;
  final skipWrites = skipAll ?? (readOnly ? 'read only run' : null);

  final requests = <(String, String)>{};
  late Dio dio;
  late EmbyAdminPluginsApi plugins;
  late EmbyAdminLiveTvApi liveTv;
  late EmbyAdminExtrasApi extras;

  setUpAll(() {
    if (skipAll != null) return;
    dio = Dio(
      BaseOptions(
        baseUrl: url!,
        headers: {
          'Authorization': buildServerAuthorizationHeader(
            scheme: 'Emby',
            deviceInfo: const DeviceInfo(
              id: 'moonfin-admin-extras-live-api',
              name: 'Admin extras live API test',
              appName: 'Moonfin',
              appVersion: 'test',
            ),
            accessToken: token,
          ),
        },
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add((o.method, o.uri.path));
          if (readOnly && o.method != 'GET') {
            return h.reject(
              DioException(requestOptions: o, error: 'read only'),
            );
          }
          h.next(o);
        },
      ),
    );
    plugins = EmbyAdminPluginsApi(dio);
    liveTv = EmbyAdminLiveTvApi(dio);
    extras = EmbyAdminExtrasApi(dio);
  });

  Future<bool> hasBackupPlugin() async => (await plugins.getInstalledPlugins())
      .any((p) => p.id.toLowerCase() == _backupPluginId);

  group('reads', skip: skipAll, () {
    test('plugins, the catalog and settings pages', () async {
      final installed = await plugins.getInstalledPlugins();
      expect(installed, isNotEmpty);
      expect(installed.map((p) => p.id), everyElement(isNotEmpty));

      final catalog = await plugins.getAvailablePackages();
      expect(catalog, isNotEmpty);
      expect(
        catalog.expand((p) => p.versions).map((v) => v.classification),
        everyElement(isNotNull),
      );

      // Catalog guids are upper case on some packages, installed ids never.
      final listed = installed.firstWhere(
        (p) => catalog.any((c) => c.id.toLowerCase() == p.id.toLowerCase()),
      );
      final package = await plugins.getPackageInfo(
        catalog
            .firstWhere((c) => c.id.toLowerCase() == listed.id.toLowerCase())
            .name,
        assemblyGuid: listed.id,
      );
      expect(package?.versions, isNotEmpty);
      expect(
        await plugins.getPackageInfo(
          'moonfin-no-such-package',
          assemblyGuid: '00000000-0000-0000-0000-000000000000',
        ),
        isNull,
      );

      final pages = await plugins.getConfigurationPages();
      expect(
        pages.map((p) => p['ConfigurationPageType']),
        everyElement('PluginConfiguration'),
      );

      final configurable = installed.firstWhere(
        (p) => p.configurationFileName != null,
      );
      expect(await plugins.getPluginConfiguration(configurable.id), isA<Map>());

      expect(await plugins.getRepositories(), isEmpty);
      await expectLater(
        plugins.disablePlugin(listed.id, listed.version),
        throwsUnsupportedError,
      );
    });

    test('live TV setup', () async {
      final types = await liveTv.getTunerHostTypes();
      expect(types.map((t) => t['Id']), contains('m3u'));
      final hosts = await liveTv.getTunerHosts();
      final providers = await liveTv.getListingProviders();
      expect(
        await liveTv.getDefaultListingProvider(),
        contains('EnableAllTuners'),
      );
      expect(await liveTv.discoverTuners(), isA<List>());

      final config = await liveTv.getLiveTvConfiguration();
      expect(
        (config['TunerHosts'] as List).map((h) => (h as Map)['Id']),
        hosts.map((h) => h['Id']),
      );
      for (final provider in providers) {
        expect(
          await liveTv.getChannelMappingOptions(provider['Id'] as String),
          contains('ProviderChannels'),
        );
      }
      await expectLater(
        liveTv.getSchedulesDirectCountries(),
        throwsUnsupportedError,
      );
    });

    test('Emby-only reads', () async {
      final premiere = await extras.getPremiereStatus();
      expect(premiere.hasKey, (await extras.getPremiereKey()) != null);

      expect(await extras.getVideoCodecInformation(), isNotEmpty);
      final toneMap = await extras.getToneMapOptions();
      expect(toneMap, containsPair('TypeName', 'ToneMapOptions'));
      expect(toneMap['Object'], isA<Map>());

      await extras.getSyncJobs(conversions: true);
      await extras.getSyncJobs(conversions: false);
      expect(await extras.getManagedChannels(limit: 5), contains('Items'));

      final sources = await extras.getAvailableListingProviders(country: 'USA');
      expect(sources.map((s) => s['Id']), contains('xmltv'));
      final german = await extras.getAvailableListingProviders(country: 'DEU');
      expect(german.map((s) => s['Id']), isNot(contains('embygn')));
    });

    test('Backup & Restore info', () async {
      if (!await hasBackupPlugin()) {
        markTestSkipped('Backup & Restore is not installed');
        return;
      }
      final info = await extras.getBackupInfo();
      expect(info['FullBackupInfo'], contains('CanRestore'));
      expect(info['LightBackups'], isA<List>());
    });
  });

  group('writes', skip: skipWrites, () {
    test('a plugin configuration saves and reads back', () async {
      if (!await hasBackupPlugin()) {
        markTestSkipped('Backup & Restore is not installed');
        return;
      }
      final before = await plugins.getPluginConfiguration(_backupPluginId);
      final retention = (before['BackupRetention'] as int? ?? 0) + 1;
      await plugins.updatePluginConfiguration(_backupPluginId, {
        ...before,
        'BackupRetention': retention,
      });
      expect(
        (await plugins.getPluginConfiguration(
          _backupPluginId,
        ))['BackupRetention'],
        retention,
      );
      await plugins.updatePluginConfiguration(_backupPluginId, before);
      expect(await plugins.getPluginConfiguration(_backupPluginId), before);
    });

    test("canceling an install that isn't running", () async {
      await plugins.cancelPackageInstallation('moonfin-no-such-install');
    });

    test('a guide provider is added, mapped and removed', () async {
      final options = (await liveTv.getLiveTvConfiguration())['ChannelOptions'];
      final added = await liveTv.addListingProvider({
        'Type': 'xmltv',
        'Path': 'http://127.0.0.1:9/moonfin-live-test.xml',
        'EnableAllTuners': true,
      });
      final id = added['Id'] as String;
      try {
        expect(
          (await liveTv.getListingProviders()).map((p) => p['Id']),
          contains(id),
        );
        // No tuner channel has this id, so nothing gets mapped, but Emby
        // still keeps channel options for it.
        expect(
          await liveTv.setChannelMapping(id, 'moonfin-live-test', 'none'),
          contains('IsManualMapping'),
        );
      } finally {
        await liveTv.removeListingProvider(id);
        await liveTv.updateLiveTvConfiguration({
          ...await liveTv.getLiveTvConfiguration(),
          'ChannelOptions': options,
        });
      }
      expect(
        (await liveTv.getListingProviders()).map((p) => p['Id']),
        isNot(contains(id)),
      );
    });

    test('a tuner is added and removed', () async {
      final added = await liveTv.addTunerHost({
        'Type': 'm3u',
        'Url': m3u,
        'FriendlyName': 'Moonfin live test',
      });
      final id = added['Id'] as String;
      try {
        expect(
          (await liveTv.getTunerHosts()).map((h) => h['Id']),
          contains(id),
        );
      } finally {
        await liveTv.removeTunerHost(id);
      }
      expect(
        (await liveTv.getTunerHosts()).map((h) => h['Id']),
        isNot(contains(id)),
      );
    }, skip: m3u == null ? 'set MOONFIN_LIVE_M3U' : null);

    test('the live TV configuration saves every key', () async {
      final before = await liveTv.getLiveTvConfiguration();
      final padding = (before['PrePaddingSeconds'] as int? ?? 0) + 60;
      await liveTv.updateLiveTvConfiguration({
        ...before,
        'PrePaddingSeconds': padding,
      });
      final after = await liveTv.getLiveTvConfiguration();
      expect(after['PrePaddingSeconds'], padding);
      expect(after.keys.toSet(), before.keys.toSet());
      await liveTv.updateLiveTvConfiguration(before);
      expect(
        (await liveTv.getLiveTvConfiguration())['PrePaddingSeconds'],
        before['PrePaddingSeconds'],
      );
    });

    test('a channel is turned off and back on', () async {
      final page = await extras.getManagedChannels(limit: 1);
      final channels = page['Items'] as List;
      if (channels.isEmpty) {
        markTestSkipped('no channels, Emby Live TV needs Premiere');
        return;
      }
      final channel = channels.first as Map;
      final id = channel['Id'] as String;
      final managementId = channel['ManagementId'] as String;
      final disabled = channel['Disabled'] == true;
      await extras.setChannelDisabled(
        id,
        managementId: managementId,
        disabled: !disabled,
      );
      await extras.setChannelDisabled(
        id,
        managementId: managementId,
        disabled: disabled,
      );
      await extras.setChannelSortIndex(
        id,
        managementId: managementId,
        newIndex: 0,
      );
    });

    test('a Premiere key saves and the old one comes back', () async {
      final before = await extras.getPremiereKey();
      try {
        await extras.setPremiereKey('moonfin-test-invalid-key');
        final status = await extras.getPremiereStatus();
        expect(status.hasKey, isTrue);
        expect(status.isKeyInvalid, isTrue);
      } finally {
        await extras.setPremiereKey(before ?? '');
      }
      expect(await extras.getPremiereKey(), before);
    });

    test(
      'Emby Connect refuses an unknown account, unlink is a no-op',
      () async {
        final user = (await dio.get<Map<String, dynamic>>(
          '/Users/$userId',
        )).data!;
        await expectLater(
          extras.linkConnectUser(userId!, 'moonfin-no-such-connect-user'),
          throwsA(isA<DioException>()),
        );
        if (user['ConnectUserName'] != null) {
          markTestSkipped('the user has an Emby Connect link to keep');
          return;
        }
        await extras.unlinkConnectUser(userId);
      },
    );

    test('canceling an unknown sync job fails', () async {
      await expectLater(
        extras.cancelSyncJob('999999999'),
        throwsA(isA<DioException>()),
      );
    });

  });

  group(
    'destructive',
    skip:
        skipWrites ??
        (env['MOONFIN_LIVE_DESTRUCTIVE'] == '1'
            ? null
            : 'set MOONFIN_LIVE_DESTRUCTIVE=1'),
    () {
      Future<void> restart() async {
        final probe = Dio(
          BaseOptions(
            baseUrl: url!,
            connectTimeout: const Duration(seconds: 2),
            receiveTimeout: const Duration(seconds: 2),
          ),
        );
        Future<bool> up() async {
          try {
            final r = await probe.get<Map<String, dynamic>>(
              '/System/Info/Public',
            );
            return r.data?['Version'] != null;
          } catch (_) {
            return false;
          }
        }

        await dio.post<void>('/System/Restart');
        // shortcut: a fixed wait, since Emby can be back before a poll sees it
        // down. The plugin list checks after it are the real signal.
        await Future<void>.delayed(const Duration(seconds: 3));
        for (var i = 0; !await up(); i++) {
          if (i > 120) fail('the server never came back');
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      Future<List<String>> pluginIds() async {
        for (var i = 0; ; i++) {
          try {
            return [for (final p in await plugins.getInstalledPlugins()) p.id];
          } on DioException {
            if (i > 30) rethrow;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }

      test(
        'a catalog plugin installs, then uninstalls after a restart',
        () async {
          const guid = '9ecaac5f-435e-4c21-b1c0-d99423b68984';
          final package = (await plugins.getAvailablePackages()).firstWhere(
            (p) => p.id.toLowerCase() == guid,
          );
          final version = package.versions.first;
          await plugins.installPackage(
            package.name,
            assemblyGuid: package.id,
            version: version.version,
            updateClass: version.classification,
          );
          // The download finishes in the background, then a restart loads it.
          for (var i = 0; ; i++) {
            final info = (await dio.get<Map<String, dynamic>>(
              '/System/Info',
            )).data!;
            final done = (info['CompletedInstallations'] as List? ?? const [])
                .any((e) => (e as Map)['Name'] == package.name);
            if (done) break;
            if (i > 60) fail('the install never finished');
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          await restart();
          expect(await pluginIds(), contains(guid));
          final installed = (await plugins.getInstalledPlugins()).firstWhere(
            (p) => p.id == guid,
          );

          await plugins.uninstallPlugin(installed.id, installed.version);
          expect(await pluginIds(), isNot(contains(guid)));
          await restart();
          expect(await pluginIds(), isNot(contains(guid)));
        },
        timeout: const Timeout(Duration(minutes: 6)),
      );
    },
  );

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
      // Routes the server keeps out of the document.
      final hidden = [RegExp(r'/Plugins/SecurityInfo$')];
      final base = Uri.parse(url!).path;
      final unknown = [
        for (final (method, path) in requests)
          if (path.substring(base.length) case final route
              when !routes.any((r) => r.$1 == method && r.$2.hasMatch(route)) &&
                  !hidden.any((h) => h.hasMatch(route)))
            '$method $route',
      ];
      expect(unknown, isEmpty);
    });
  });
}
