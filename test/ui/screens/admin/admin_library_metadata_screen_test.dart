import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/libraries/admin_library_metadata_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> server = {
    'PreferredMetadataLanguage': 'en',
    'MetadataCountryCode': 'US',
    'DummyChapterDuration': 0,
    'ChapterImageResolution': 'MatchSource',
    'MinResumePct': 5,
  };
  bool failCultures = false;
  final posted = <Map<String, dynamic>>[];
  Map<String, dynamic> metadata = {'UseFileCreationTimeForDateAdded': true};
  final namedPosts = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    expect(key, 'metadata');
    return Map<String, dynamic>.from(metadata);
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    namedPosts[key] = config;
    metadata = Map<String, dynamic>.from(config);
  }

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async =>
      Map<String, dynamic>.from(server);

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
    posted.add(config);
    server = Map<String, dynamic>.from(config);
  }

  @override
  Future<List<Map<String, dynamic>>> getCultures() async {
    if (failCultures) throw Exception('cultures down');
    return [
      {'DisplayName': 'English', 'TwoLetterISOLanguageName': 'en'},
      {'DisplayName': 'German', 'TwoLetterISOLanguageName': 'de'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getCountries() async => [
    {'DisplayName': 'United States', 'TwoLetterISORegionName': 'US'},
  ];
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

  Future<void> pump(WidgetTester tester, {bool onEmby = false}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const page = AdminLibraryMetadataScreen();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: onEmby
              ? const AdminServerScope(serverType: ServerType.emby, child: page)
              : page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder intervalField() => find.descendant(
    of: find.ancestor(
      of: find.text(l10n.adminLibDummyChapterDuration),
      matching: find.byType(Padding),
    ).first,
    matching: find.byType(EditableText),
  );

  testWidgets('the number, the code and the enum dropdowns save', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(intervalField(), '12');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('German').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminLibChapterImageResolutionMatchSource));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p').last);
    await tester.pumpAndSettle();

    api.server = {...api.server, 'MinResumePct': 9};
    expect(await AdminDraft.active.value!.save(), isTrue);

    final body = api.posted.single;
    expect(body['DummyChapterDuration'], 12);
    expect(body['PreferredMetadataLanguage'], 'de');
    expect(body['ChapterImageResolution'], 'P720');
    expect(body['MinResumePct'], 9);
  });

  testWidgets('the interval takes no minus sign', (tester) async {
    await pump(tester);

    await tester.enterText(intervalField(), '-5');
    await tester.pump();
    await AdminDraft.active.value!.save();

    expect(api.posted.single['DummyChapterDuration'], 5);
  });

  testWidgets('a failed language list shows the error', (
    tester,
  ) async {
    api.failCultures = true;
    await pump(tester);

    expect(find.text(l10n.adminSettingsLoadFailed), findsOneWidget);
    expect(AdminDraft.active.value, isNull);
  });

  testWidgets('Jellyfin keeps date added on its Display page', (tester) async {
    await pump(tester);
    expect(find.text(l10n.adminLibDateAddedLabel), findsNothing);
    expect(api.namedPosts, isEmpty);
  });

  testWidgets('on Emby date added and suggestions replace the chapters', (
    tester,
  ) async {
    // Emby's base configuration, which has no chapter settings.
    api.server = {
      'MetadataCountryCode': 'US',
      'EnableExternalContentInSuggestions': true,
    };
    await pump(tester, onEmby: true);

    expect(find.text(l10n.adminLibDummyChapterDuration), findsNothing);
    await tester.tap(find.text(l10n.adminLibDateAddedFile));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminLibDateAddedImport).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminLibExternalSuggestions));
    await tester.pump();

    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.namedPosts['metadata'], {'UseFileCreationTimeForDateAdded': false});
    expect(api.posted.single['EnableExternalContentInSuggestions'], isFalse);
    expect(api.posted.single.containsKey('DummyChapterDuration'), isFalse);
  });
}
