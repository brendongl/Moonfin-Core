import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_resume_settings_screen.dart';
import 'package:moonfin/ui/screens/admin/widgets/admin_settings_search.dart';
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
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminResumeSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byWidgetPredicate(
    (w) => w is AdminSettingAnchor && w.id == 'resume.$key',
  );

  Finder field(String key) =>
      find.descendant(of: row(key), matching: find.byType(TextFormField));

  testWidgets('audiobook values are minutes and round-trip as minutes', (
    tester,
  ) async {
    api.server = {...api.server, 'MinAudiobookResume': 7, 'MaxAudiobookResume': 4};
    await pump(tester);

    expect(find.text(l10n.adminResumeMinAudiobookMinutes), findsOneWidget);
    expect(find.text(l10n.adminResumeAudiobookRemaining), findsOneWidget);
    for (final key in ['MinAudiobookResume', 'MaxAudiobookResume']) {
      expect(
        find.descendant(of: row(key), matching: find.textContaining('%')),
        findsNothing,
      );
    }
    expect(find.descendant(of: field('MinAudiobookResume'), matching: find.text('7')),
        findsOneWidget);
    expect(find.descendant(of: field('MaxAudiobookResume'), matching: find.text('4')),
        findsOneWidget);

    await tester.enterText(field('MinAudiobookResume'), '12');
    await tester.enterText(field('MaxAudiobookResume'), '0');
    await tester.pump();
    expect(await AdminDraft.active.value!.save(), isTrue);

    expect(api.posted.single['MinAudiobookResume'], 12);
    // Remaining minutes can't go below 1.
    expect(api.posted.single['MaxAudiobookResume'], 1);
  });

  testWidgets('a slider and a number field post their values', (tester) async {
    await pump(tester);
    tester
        .widget<Slider>(
          find.descendant(of: row('MinResumePct'), matching: find.byType(Slider)),
        )
        .onChanged!(42);
    await tester.pump();
    await tester.enterText(field('MinResumeDurationSeconds'), '600');
    await tester.pump();

    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.posted.single['MinResumePct'], 42);
    expect(api.posted.single['MinResumeDurationSeconds'], 600);
    expect(api.posted.single['MaxResumePct'], 90);
  });

  testWidgets('save keeps keys another page changed meanwhile', (tester) async {
    await pump(tester);
    await tester.enterText(field('MinAudiobookResume'), '9');
    await tester.pump();

    api.server = {...api.server, 'ServerName': 'Renamed'};
    await AdminDraft.active.value!.save();

    expect(api.posted.single['ServerName'], 'Renamed');
    expect(api.posted.single['MinAudiobookResume'], 9);
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
