import 'package:dio/dio.dart';
import 'package:server_emby/src/api/emby_admin_plugins_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  late AdminFake fake;
  late EmbyAdminPluginsApi api;

  setUp(() {
    fake = AdminFake();
    api = EmbyAdminPluginsApi(fake.dio);
  });

  test("installed plugins read Emby's ImageTag", () async {
    fake.responses['/Plugins'] = [
      {
        'Name': 'Backup & Restore',
        'Version': '1.8.7.0',
        'ConfigurationFileName': 'MBBackup.xml',
        'Id': 'e711475e-efad-431b-8527-033ba9873a34',
        'ImageTag': '1',
      },
    ];

    final [plugin] = await api.getInstalledPlugins();

    expect(plugin.name, 'Backup & Restore');
    expect(plugin.hasImage, isTrue);
    expect(plugin.configurationFileName, 'MBBackup.xml');
  });

  test('enable, disable and repositories are unsupported', () async {
    await expectLater(api.enablePlugin('a', '1'), throwsUnsupportedError);
    await expectLater(api.disablePlugin('a', '1'), throwsUnsupportedError);
    await expectLater(api.setRepositories(const []), throwsUnsupportedError);
    expect(await api.getRepositories(), isEmpty);
    expect(fake.requests, isEmpty);
  });

  test('uninstall posts to the plugin without a version', () async {
    await api.uninstallPlugin('abc', '1.0.0.0');

    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/Plugins/abc/Delete');
  });

  test('the catalog asks for server plugins only', () async {
    fake.responses['/Packages'] = [
      {
        'name': 'Backup & Restore',
        'guid': 'e711475e-efad-431b-8527-033ba9873a34',
        'shortDescription': 'Backup and restore',
        'isPremium': true,
        'versions': [
          {'versionStr': '1.8.7.0', 'classification': 'Release'},
        ],
      },
    ];

    final [package] = await api.getAvailablePackages();

    expect(fake.last.queryParameters, {
      'TargetSystems': 'Server',
      'IsAdult': false,
      'PackageType': 'UserInstalled',
    });
    expect(package.isPremium, isTrue);
    expect(package.versions.single.classification, 'Release');
  });

  test('configuration pages are filtered to settings pages', () async {
    fake.responses['/web/ConfigurationPages'] = [
      {'Name': 'embybackup', 'PluginId': 'x', 'EnableInMainMenu': true},
    ];

    final pages = await api.getConfigurationPages();

    expect(fake.last.queryParameters, {'PageType': 'PluginConfiguration'});
    expect(pages.single['Name'], 'embybackup');
  });

  test('an unknown package is null, other errors still throw', () async {
    final path = '/Packages/${Uri.encodeComponent('Not There')}';
    fake.statuses[path] = 400;
    expect(await api.getPackageInfo('Not There', assemblyGuid: 'g'), isNull);
    expect(fake.last.queryParameters, {'AssemblyGuid': 'g'});

    fake.statuses[path] = 500;
    await expectLater(
      api.getPackageInfo('Not There'),
      throwsA(isA<DioException>()),
    );
  });

  test('install sends the release channel and drops the repository', () async {
    await api.installPackage(
      'Backup & Restore',
      assemblyGuid: 'g',
      version: '1.8.6',
      repositoryUrl: 'https://example.invalid',
      updateClass: 'Beta',
    );

    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/Packages/Installed/Backup%20%26%20Restore');
    expect(fake.last.queryParameters, {
      'AssemblyGuid': 'g',
      'Version': '1.8.6',
      'UpdateClass': 'Beta',
    });
  });

  test('canceling an install posts its delete route', () async {
    await api.cancelPackageInstallation('job1');

    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/Packages/Installing/job1/Delete');
  });
}
