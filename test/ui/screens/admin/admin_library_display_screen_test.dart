import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/libraries/admin_library_display_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> server = {
    'EnableFolderView': false,
    'DisplaySpecialsWithinSeasons': true,
    'EnableGroupingMoviesIntoCollections': false,
    'EnableGroupingShowsIntoCollections': false,
    'EnableExternalContentInSuggestions': true,
    'MinResumePct': 5,
  };
  Map<String, dynamic> metadata = {'UseFileCreationTimeForDateAdded': true};
  bool failMetadata = false;
  final calls = <String>[];
  final posted = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async =>
      Map<String, dynamic>.from(server);

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
    calls.add('POST /System/Configuration');
    posted['config'] = config;
    server = Map<String, dynamic>.from(config);
  }

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    expect(key, 'metadata');
    if (failMetadata) throw Exception('metadata down');
    return Map<String, dynamic>.from(metadata);
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    calls.add('POST /System/Configuration/$key');
    posted[key] = config;
    metadata = Map<String, dynamic>.from(config);
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
        home: const Scaffold(body: AdminLibraryDisplayScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a switch and the dropdown save to their own configs', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminLibFolderView));
    await tester.pump();
    await tester.tap(find.text(l10n.adminLibDateAddedFile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminLibDateAddedImport).last);
    await tester.pumpAndSettle();

    // Another page saved the server config in between.
    api.server = {...api.server, 'MinResumePct': 9};
    expect(await AdminDraft.active.value!.save(), isTrue);

    expect(api.calls, [
      'POST /System/Configuration',
      'POST /System/Configuration/metadata',
    ]);
    expect(api.posted['config']!['EnableFolderView'], isTrue);
    expect(api.posted['config']!['MinResumePct'], 9);
    expect(api.posted['metadata'], {'UseFileCreationTimeForDateAdded': false});
  });

  testWidgets('only the changed config is posted', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.adminLibGroupMovies));
    await tester.pump();

    await AdminDraft.active.value!.save();

    expect(api.calls, ['POST /System/Configuration']);
  });

  // Saving {} over the metadata config would turn "Use file creation date" on
  // without asking.
  testWidgets('a failed metadata load shows the error and offers no save', (
    tester,
  ) async {
    api.failMetadata = true;
    await pump(tester);

    expect(find.text(l10n.adminSettingsLoadFailed), findsOneWidget);
    expect(find.text(l10n.adminLibFolderView), findsNothing);
    expect(AdminDraft.active.value, isNull);
    expect(api.calls, isEmpty);
  });

  testWidgets('a missing date added key shows the server default', (
    tester,
  ) async {
    api.metadata = {};
    await pump(tester);

    expect(find.text(l10n.adminLibDateAddedFile), findsOneWidget);
    expect(find.text(l10n.adminLibDateAddedImport), findsNothing);
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
