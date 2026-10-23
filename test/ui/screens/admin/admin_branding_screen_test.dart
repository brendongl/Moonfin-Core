import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_branding_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves the stored BrandingOptions (GET /System/Configuration/branding) and
/// records every post.
class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> server = {
    'LoginDisclaimer': 'Hello',
    'CustomCss': '',
    'SplashscreenEnabled': false,
    'SplashscreenLocation': '/config/splashscreen.png',
  };
  final posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    expect(key, 'branding');
    return Map<String, dynamic>.from(server);
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    expect(key, 'branding');
    posted.add(config);
    server = Map<String, dynamic>.from(config);
  }
}

void main() {
  late _FakeSystemApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    when(() => client.baseUrl).thenReturn('http://jf.test');
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminBrandingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Padding)).first,
    matching: find.byType(TextFormField),
  );

  testWidgets('text edits go through the draft and keep the splash location', (
    tester,
  ) async {
    await pump(tester);
    final draft = AdminDraft.active.value!;

    await tester.enterText(field(l10n.adminBrandingLoginDisclaimer), 'Welcome');
    await tester.enterText(field(l10n.adminBrandingCustomCss), 'body {}');
    await tester.pump();
    expect(draft.isDirty, isTrue);
    expect(api.posted, isEmpty);

    expect(await draft.save(), isTrue);
    expect(api.posted.single, {
      'LoginDisclaimer': 'Welcome',
      'CustomCss': 'body {}',
      'SplashscreenEnabled': false,
      'SplashscreenLocation': '/config/splashscreen.png',
    });
  });

  testWidgets('the splash switch saves at once and stays out of the draft', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field(l10n.adminBrandingLoginDisclaimer), 'Welcome');
    await tester.pump();

    await tester.tap(find.text(l10n.adminBrandingEnableSplash));
    await tester.pumpAndSettle();

    // Only the switch went out, not the unsaved disclaimer.
    expect(api.posted.single['SplashscreenEnabled'], isTrue);
    expect(api.posted.single['LoginDisclaimer'], 'Hello');

    final draft = AdminDraft.active.value!;
    await draft.save();
    expect(api.posted.last['SplashscreenEnabled'], isTrue);
    expect(api.posted.last['LoginDisclaimer'], 'Welcome');
  });

  testWidgets('upload and delete are off while the splash screen is off', (
    tester,
  ) async {
    await pump(tester);

    FilledButton upload() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(l10n.adminBrandingSplashUpload).last,
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(upload().onPressed, isNull);
    expect(find.text(l10n.adminBrandingSplashSizeHint), findsOneWidget);

    await tester.tap(find.text(l10n.adminBrandingEnableSplash));
    await tester.pumpAndSettle();
    expect(upload().onPressed, isNotNull);
  });

  testWidgets('loads clean, with no save button of its own', (tester) async {
    await pump(tester);
    expect(AdminDraft.active.value!.isDirty, isFalse);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
