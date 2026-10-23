import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_streaming_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// A 12.2 server's ServerConfiguration.
Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/admin/server_configuration.json').readAsStringSync())
        as Map<String, dynamic>;

class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> server = _fixture();
  final posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async =>
      jsonDecode(jsonEncode(server)) as Map<String, dynamic>;

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
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
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminStreamingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String shown(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  Future<int> postAfterTyping(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextFormField), text);
    await tester.pump();
    expect(await AdminDraft.active.value!.save(), isTrue);
    // Save re-keys the field, let that frame run before the next edit.
    await tester.pumpAndSettle();
    return api.posted.last['RemoteClientBitrateLimit'] as int;
  }

  testWidgets('shows the stored limit in Mbps without rounding', (
    tester,
  ) async {
    api.server['RemoteClientBitrateLimit'] = 2250000;
    await pump(tester);
    expect(shown(tester), '2.25');
  });

  testWidgets('no limit shows an empty field', (tester) async {
    await pump(tester);
    expect(shown(tester), '');
  });

  testWidgets('Mbps converts to bits and caps at what an int holds', (
    tester,
  ) async {
    await pump(tester);
    expect(await postAfterTyping(tester, '2.25'), 2250000);
    expect(await postAfterTyping(tester, '5000'), 2147250000);
    expect(await postAfterTyping(tester, ''), 0);
  });

  testWidgets('save keeps keys another page changed meanwhile', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), '8');
    await tester.pump();
    api.server = {...api.server, 'MinResumePct': 9};

    await AdminDraft.active.value!.save();
    expect(api.posted.single['MinResumePct'], 9);
    expect(api.posted.single['RemoteClientBitrateLimit'], 8000000);
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
