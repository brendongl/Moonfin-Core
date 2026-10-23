import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/emby/admin_config_form.dart';
import 'package:moonfin/ui/screens/admin/emby/emby_config_pages.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> cinemamode = {
    'EnableIntrosForMovies': false,
    'EnableIntrosForWatchedContent': false,
    'MaximizeRandomization': false,
    'TrailerLimit': 2,
  };
  Map<String, dynamic> server = {
    'LocalNetworkSubnets': ['10.0.0.0/8'],
    'IsRemoteIPFilterBlacklist': false,
    'ProxyHeaderMode': 'AllAddresses',
    'HttpServerPortNumber': 8096,
  };
  final posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async =>
      Map<String, dynamic>.from(server);

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
    posted.add(config);
    server = Map<String, dynamic>.from(config);
  }

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    expect(key, 'cinemamode');
    return Map<String, dynamic>.from(cinemamode);
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    posted.add(config);
    cinemamode = Map<String, dynamic>.from(config);
  }
}

class _FakeEmbyApi extends Fake implements EmbyAdminApi {
  bool active = false;

  @override
  Future<PremiereStatus> getPremiereStatus() async =>
      PremiereStatus(isActive: active, hasKey: active);
}

void main() {
  late _FakeSystemApi api;
  late _FakeEmbyApi emby;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    emby = _FakeEmbyApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    when(() => client.embyAdminApi).thenReturn(emby);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester, [AdminConfigPage? page]) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AdminServerScope(
              serverType: ServerType.emby,
              child: AdminConfigFormScreen(page: page ?? cinemaIntrosPage),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder toggle(String label) => find.widgetWithText(SwitchListTile, label);

  testWidgets('inverted toggles show and save the opposite flag', (
    tester,
  ) async {
    await pump(tester);
    final similarOnly = tester.widget<SwitchListTile>(
      toggle(l10n.adminCinemaIntrosSimilarOnly),
    );
    expect(similarOnly.value, isTrue);

    await tester.tap(toggle(l10n.adminCinemaIntrosSimilarOnly));
    await tester.pumpAndSettle();
    expect(await AdminDraft.active.value!.save(), isTrue);

    expect(api.posted.single['MaximizeRandomization'], isTrue);
    expect(api.posted.single['TrailerLimit'], 2);
  });

  testWidgets('without Premiere the page says so', (tester) async {
    await pump(tester);
    expect(find.text(l10n.adminPremiereNote), findsOneWidget);
  });

  testWidgets('with Premiere there is no note', (tester) async {
    emby.active = true;
    await pump(tester);
    expect(find.text(l10n.adminPremiereNote), findsNothing);
  });

  testWidgets('list fields take one entry per line', (tester) async {
    await pump(tester, embyNetworkingPage);
    expect(find.text('10.0.0.0/8'), findsOneWidget);

    await tester.enterText(
      find.text('10.0.0.0/8'),
      '10.0.0.0/8\n\n  192.168.1.0/24 \n',
    );
    await tester.pump();
    expect(await AdminDraft.active.value!.save(), isTrue);

    expect(api.posted.single['LocalNetworkSubnets'], [
      '10.0.0.0/8',
      '192.168.1.0/24',
    ]);
  });

  testWidgets('choice fields save the stored value', (tester) async {
    await pump(tester, embyNetworkingPage);

    await tester.tap(find.text(l10n.adminNetworkingWhitelist));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminNetworkingBlacklist).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.yes));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminNetworkingProxyHeadersRemote).last);
    await tester.pumpAndSettle();
    expect(await AdminDraft.active.value!.save(), isTrue);

    expect(api.posted.single['IsRemoteIPFilterBlacklist'], isTrue);
    expect(api.posted.single['ProxyHeaderMode'], 'RemoteAddressesOnly');
    expect(api.posted.single['HttpServerPortNumber'], 8096);
  });

  testWidgets('a value the choices lack still shows and saves as is', (
    tester,
  ) async {
    api.server['ProxyHeaderMode'] = 'SomethingNew';
    await pump(tester, embyNetworkingPage);
    expect(find.text('SomethingNew'), findsOneWidget);

    await tester.tap(find.text(l10n.adminNetworkingWhitelist));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminNetworkingBlacklist).last);
    await tester.pumpAndSettle();
    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.posted.single['ProxyHeaderMode'], 'SomethingNew');
  });

  testWidgets('port fields stay within range', (tester) async {
    await pump(tester, embyNetworkingPage);
    await tester.enterText(find.text('8096'), '70000');
    await tester.pump();
    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.posted.single['HttpServerPortNumber'], 65535);
  });
}
