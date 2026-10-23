import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/keys/admin_api_keys_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeKeysApi extends Fake implements AdminApiKeysApi {
  final keys = <Map<String, dynamic>>[
    {
      'AccessToken': 'aaaa1111bbbb2222',
      'AppName': 'Scripts',
      'DateCreated': '2026-10-01T10:00:00Z',
    },
  ];
  final created = <String>[];
  final revoked = <String>[];

  @override
  Future<Map<String, dynamic>> getApiKeys() async =>
      {'Items': [...keys], 'TotalRecordCount': keys.length};

  @override
  Future<void> createApiKey(String appName) async {
    created.add(appName);
    keys.add({'AccessToken': 'newtoken12345678', 'AppName': appName});
  }

  @override
  Future<void> revokeApiKey(String key) async => revoked.add(key);
}

void main() {
  late _FakeKeysApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeKeysApi();
    final client = _MockMediaServerClient();
    when(() => client.adminApiKeysApi).thenReturn(api);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminApiKeysScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('create posts the app name and shows the new key', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.adminCreateKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Backup');
    await tester.tap(find.widgetWithText(FilledButton, l10n.create));
    await tester.pumpAndSettle();

    expect(api.created, ['Backup']);
    expect(find.text('newtoken12345678'), findsOneWidget);
  });

  testWidgets('revoke asks first and revokes that token', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip(l10n.revoke));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.revoke));
    await tester.pumpAndSettle();

    expect(api.revoked, ['aaaa1111bbbb2222']);
  });
}
