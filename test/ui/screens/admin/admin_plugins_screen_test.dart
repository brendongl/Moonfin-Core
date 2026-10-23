import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/plugins/admin_plugins_screen.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_user_providers.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Records the list-level actions the screen sends.
class _FakePluginsApi extends Fake implements AdminPluginsApi {
  final installs = <Map<String, String?>>[];

  @override
  Future<void> installPackage(
    String name, {
    String? assemblyGuid,
    String? version,
    String? repositoryUrl,
    String? updateClass,
  }) async {
    installs.add({
      'name': name,
      'assemblyGuid': assemblyGuid,
      'version': version,
      'repositoryUrl': repositoryUrl,
    });
  }
}

PackageInfo _package(String name, String repositoryUrl) => PackageInfo(
  name: name,
  id: '${name.toLowerCase()}-guid',
  versions: [
    VersionInfo(
      version: '2.0.0.0',
      repositoryName: 'Repo',
      repositoryUrl: repositoryUrl,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePluginsApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakePluginsApi();
    final client = _MockMediaServerClient();
    when(() => client.adminPluginsApi).thenReturn(api);
    when(() => client.baseUrl).thenReturn('http://emby.test/emby');
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<PluginInfo> installedPlugins,
    List<PackageInfo> availablePackages = const [],
    ServerType server = ServerType.jellyfin,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminInstalledPluginsProvider.overrideWith(
            (ref) async => installedPlugins,
          ),
          adminAvailablePackagesProvider.overrideWith(
            (ref) async => availablePackages,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminServerScope(
            serverType: server,
            child: const Scaffold(body: AdminPluginsScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCatalog(WidgetTester tester) async {
    await tester.tap(find.text(l10n.adminPluginsCatalog));
    await tester.pumpAndSettle();
  }

  testWidgets('installed filters use filter-specific empty states', (
    tester,
  ) async {
    await pumpScreen(tester, installedPlugins: const []);

    expect(find.text(l10n.adminPluginsNoneInstalled), findsOneWidget);

    await tester.tap(find.text(l10n.adminPluginsActive));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminPluginsNoneActive), findsOneWidget);

    await tester.tap(find.text(l10n.adminPluginsRestartRequired));
    await tester.pumpAndSettle();

    expect(find.text(l10n.all), findsOneWidget);
    expect(find.text(l10n.adminPluginsActive), findsOneWidget);
    expect(find.text(l10n.adminPluginsRestartRequired), findsOneWidget);
    expect(find.text(l10n.adminPluginsNoneRequireRestart), findsOneWidget);
  });

  testWidgets('only removable plugins offer enable and disable', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      installedPlugins: const [
        PluginInfo(name: 'TMDb', id: 'tmdb', version: '12.2.0.0'),
        PluginInfo(
          name: 'Moonbase',
          id: 'moonbase',
          version: '2.4.0.0',
          canUninstall: true,
        ),
      ],
    );

    // The bundled plugin has nothing to offer, so it has no menu.
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminPluginsDisable), findsOneWidget);
    expect(find.text(l10n.uninstall), findsOneWidget);
  });

  testWidgets('installing from an outside repository asks first', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      installedPlugins: const [],
      availablePackages: [
        _package('Moonbase', 'https://raw.githubusercontent.com/x/manifest.json'),
      ],
    );
    await openCatalog(tester);

    await tester.tap(find.widgetWithText(FilledButton, l10n.install));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminPluginInstallConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(api.installs, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, l10n.install));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.install).last);
    await tester.pumpAndSettle();
    expect(api.installs, [
      {
        'name': 'Moonbase',
        'assemblyGuid': 'moonbase-guid',
        'version': '2.0.0.0',
        'repositoryUrl': 'https://raw.githubusercontent.com/x/manifest.json',
      },
    ]);
  });

  testWidgets('the Jellyfin repository installs without asking', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      installedPlugins: const [],
      availablePackages: [
        _package('Fanart', 'https://repo.jellyfin.org/files/plugin/manifest.json'),
      ],
    );
    await openCatalog(tester);

    await tester.tap(find.widgetWithText(FilledButton, l10n.install));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminPluginInstallConfirmTitle), findsNothing);
    expect(api.installs.single['name'], 'Fanart');
  });

  group('on Emby', () {
    const backup = PluginInfo(
      name: 'Backup & Restore',
      id: 'e711475e-efad-431b-8527-033ba9873a34',
      version: '1.8.7.0',
      hasImage: true,
      imageTag: '1',
    );

    testWidgets('any plugin uninstalls, none turns off, nothing to filter', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        installedPlugins: const [backup],
        server: ServerType.emby,
      );

      expect(find.text(l10n.adminPluginsRestartRequired), findsNothing);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text(l10n.uninstall), findsOneWidget);
      expect(find.text(l10n.adminPluginsDisable), findsNothing);
    });

    testWidgets('the image is the plugin thumb with its tag', (tester) async {
      await pumpScreen(
        tester,
        installedPlugins: const [backup],
        server: ServerType.emby,
      );

      final image = tester.widget<Image>(find.byType(Image)).image;
      expect(
        (image as NetworkImage).url,
        'http://emby.test/emby/Plugins/e711475e-efad-431b-8527-033ba9873a34'
        '/Thumb?tag=1',
      );
    });

    testWidgets('an upper case catalog id still finds the update', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        installedPlugins: const [backup],
        availablePackages: [
          PackageInfo.fromJson({
            'name': 'Backup & Restore',
            'guid': 'E711475E-EFAD-431B-8527-033BA9873A34',
            'versions': [
              {'versionStr': '1.9.0.0'},
            ],
          }),
        ],
        server: ServerType.emby,
      );

      expect(find.text(l10n.adminPluginsUpdateAvailable('1.9.0.0')),
          findsOneWidget);
    });

    testWidgets('a premium package says it needs Premiere', (tester) async {
      await pumpScreen(
        tester,
        installedPlugins: const [],
        availablePackages: const [
          PackageInfo(name: 'Backup & Restore', id: 'b', isPremium: true),
          PackageInfo(name: 'Fanart', id: 'f'),
        ],
        server: ServerType.emby,
      );
      await openCatalog(tester);

      expect(find.text(l10n.adminPluginNeedsPremiere), findsOneWidget);
    });
  });
}
