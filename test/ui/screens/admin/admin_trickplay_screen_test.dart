import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_trickplay_screen.dart';
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
    server = jsonDecode(jsonEncode(config)) as Map<String, dynamic>;
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
        home: const Scaffold(body: AdminTrickplayScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byWidgetPredicate(
    (w) => w is AdminSettingAnchor && w.id == 'trickplay.$key',
  );

  Finder field(String key) =>
      find.descendant(of: row(key), matching: find.byType(TextFormField));

  testWidgets('edits the nested options and posts the whole object', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(row('EnableHwAcceleration'));
    await tester.pump();
    await tester.tap(find.descendant(
      of: row('ScanBehavior'),
      matching: find.byType(DropdownButtonFormField<String>),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminTrickplayBlocking).last);
    await tester.pumpAndSettle();
    await tester.enterText(field('WidthResolutions'), '320, 640');
    await tester.enterText(field('Interval'), '0');
    await tester.enterText(field('TileWidth'), '');
    tester
        .widget<Slider>(
          find.descendant(of: row('JpegQuality'), matching: find.byType(Slider)),
        )
        .onChanged!(80);
    await tester.pump();

    // Another page saved a top-level key meanwhile.
    api.server = {...api.server, 'ServerName': 'Renamed'};
    expect(await AdminDraft.active.value!.save(), isTrue);

    final body = api.posted.single;
    expect(body['ServerName'], 'Renamed');
    expect(body['TrickplayOptions'], {
      'EnableHwAcceleration': true,
      'EnableHwEncoding': false,
      'EnableKeyFrameOnlyExtraction': false,
      'ScanBehavior': 'Blocking',
      'ProcessPriority': 'BelowNormal',
      'Interval': 1,
      'WidthResolutions': [320, 640],
      'TileWidth': 10,
      'TileHeight': 10,
      'Qscale': 4,
      'JpegQuality': 80,
      'ProcessThreads': 1,
    });
  });

  testWidgets('discard puts nested edits back', (tester) async {
    await pump(tester);
    await tester.enterText(field('TileHeight'), '20');
    await tester.pump();
    expect(AdminDraft.active.value!.isDirty, isTrue);

    AdminDraft.active.value!.discard();
    await tester.pumpAndSettle();

    expect(find.descendant(of: field('TileHeight'), matching: find.text('10')),
        findsOneWidget);
    expect(AdminDraft.active.value!.isDirty, isFalse);
    expect(api.posted, isEmpty);
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
