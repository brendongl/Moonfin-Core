import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/libraries/admin_library_edit_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// A server that keeps one library and moves its folders the way Jellyfin
/// does: a path change updates Locations and the stored PathInfos at once.
class _FakeLibraryApi extends Fake implements AdminLibraryApi {
  _FakeLibraryApi(this.type);

  final String? type;
  List<String> locations = ['/media/main'];
  Map<String, dynamic> options = {
    'Enabled': true,
    'EnableRealtimeMonitor': false,
    'EnableTrickplayImageExtraction': false,
    'ExtractTrickplayImagesDuringLibraryScan': false,
    'SaveTrickplayWithMedia': false,
    'EnableEmbeddedTitles': false,
    'AutomaticRefreshIntervalDays': 0,
    'CustomTagDelimiters': ['/'],
    'PathInfos': [
      {'Path': '/media/main'},
    ],
    'TypeOptions': [],
  };
  final calls = <String>[];
  final posted = <Map<String, dynamic>>[];
  // More AvailableOptions keys for the Movie type.
  Map<String, dynamic> movieExtras = const {};
  // More AvailableOptions keys, such as Emby's LyricsFetchers.
  Map<String, dynamic> availableExtras = const {};

  void _syncPaths() => options['PathInfos'] = [
    for (final p in locations) {'Path': p},
  ];

  @override
  Future<List<VirtualFolderInfo>> getVirtualFolders() async => [
    VirtualFolderInfo.fromJson({
      'Name': 'Main',
      'ItemId': 'lib1',
      'CollectionType': ?type,
      'Locations': [...locations],
      'LibraryOptions': Map<String, dynamic>.from(options),
    }),
  ];

  @override
  Future<Map<String, dynamic>> getAvailableLibraryOptions(
    String? contentType,
  ) async => {
    'MetadataSavers': [
      {'Name': 'Nfo', 'DefaultEnabled': true},
    ],
    'MetadataReaders': [
      {'Name': 'Nfo', 'DefaultEnabled': true},
    ],
    'SubtitleFetchers': [],
    'LyricFetchers': [],
    'MediaSegmentProviders': [],
    'TypeOptions': [
      {
        'Type': 'Movie',
        'MetadataFetchers': [
          {'Name': 'TheMovieDb', 'DefaultEnabled': true},
          {'Name': 'The Open Movie Database', 'DefaultEnabled': true},
        ],
        'ImageFetchers': [],
        'SimilarItemProviders': [],
        ...movieExtras,
      },
    ],
    ...availableExtras,
  };

  @override
  Future<void> addMediaPath(
    String libraryName,
    String path, {
    bool refreshLibrary = false,
    String? libraryId,
  }) async {
    calls.add('add $libraryName $path refresh=$refreshLibrary');
    locations.add(path);
    _syncPaths();
  }

  @override
  Future<void> removeMediaPath(
    String libraryName,
    String path, {
    bool refreshLibrary = false,
    String? libraryId,
  }) async {
    calls.add('remove $libraryName $path refresh=$refreshLibrary');
    locations.remove(path);
    _syncPaths();
  }

  @override
  Future<void> updateLibraryOptions(
    String libraryId,
    Map<String, dynamic> options,
  ) async {
    calls.add('options $libraryId');
    posted.add(options);
    this.options = Map<String, dynamic>.from(options);
  }
}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  @override
  Future<List<Map<String, dynamic>>> getCultures() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getCountries() async => const [];
}

class _FakeEnvironmentApi extends Fake implements AdminEnvironmentApi {
  @override
  Future<List<Map<String, dynamic>>> getDrives() async => const [];

  @override
  Future<void> validatePath(
    String path, {
    bool writable = false,
    bool? isFile,
  }) async {}
}

void main() {
  late _FakeLibraryApi api;
  late AppLocalizations l10n;

  Future<void> setUpServer({String? type = 'movies'}) async {
    api = _FakeLibraryApi(type);
    final client = _MockMediaServerClient();
    when(() => client.adminLibraryApi).thenReturn(api);
    when(() => client.adminSystemApi).thenReturn(_FakeSystemApi());
    when(() => client.adminEnvironmentApi).thenReturn(_FakeEnvironmentApi());
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  }

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester, {bool onEmby = false}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const page = AdminLibraryEditScreen(libraryId: 'lib1');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: onEmby
                ? const AdminServerScope(
                    serverType: ServerType.emby,
                    child: page,
                  )
                : page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  Future<void> addPath(WidgetTester tester, String path) async {
    await openTab(tester, l10n.adminLibraryTabPaths);
    await tester.tap(find.text(l10n.adminAddPath));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, l10n.path), path);
    await tester.tap(find.text(l10n.select));
    await tester.pumpAndSettle();
  }

  testWidgets('a switch and a downloader tick save the library options', (
    tester,
  ) async {
    await setUpServer();
    await pump(tester);

    await openTab(tester, l10n.adminLibraryTabOptions);
    await tester.tap(find.text(l10n.adminLibRealtimeMonitor));
    await tester.pump();
    await openTab(tester, l10n.adminLibraryTabDownloaders);
    // Untick The Open Movie Database, the second Movie downloader.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();

    expect(await AdminDraft.active.value!.save(), isTrue);

    final body = api.posted.single;
    expect(body['EnableRealtimeMonitor'], isTrue);
    expect(body['TypeOptions'], [
      {
        'Type': 'Movie',
        'MetadataFetcherOrder': ['TheMovieDb', 'The Open Movie Database'],
        'MetadataFetchers': ['TheMovieDb'],
      },
    ]);
  });

  // Each supported image type is saved on or off, plus the backdrop entry.
  testWidgets('fetcher settings save the image options for the type', (
    tester,
  ) async {
    await setUpServer();
    api.movieExtras = {
      'ImageFetchers': [
        {'Name': 'TheMovieDb', 'DefaultEnabled': true},
      ],
      'SupportedImageTypes': ['Primary', 'Backdrop', 'Logo', 'Thumb'],
      'DefaultImageOptions': [
        {'Type': 'Backdrop', 'Limit': 1, 'MinWidth': 1280},
        {'Type': 'Logo', 'Limit': 1, 'MinWidth': 0},
      ],
    };
    await pump(tester);
    await openTab(tester, l10n.adminLibraryTabDownloaders);
    await tester.tap(find.text(l10n.adminLibFetcherSettings));
    await tester.pumpAndSettle();

    // Logo starts on from the server default, Thumb off.
    await tester.tap(find.text(l10n.adminMetadataImageThumb));
    await tester.enterText(
      find.widgetWithText(TextField, l10n.adminLibMaxBackdrops),
      '3',
    );
    await tester.tap(find.text(l10n.done));
    await tester.pumpAndSettle();

    expect(await AdminDraft.active.value!.save(), isTrue);
    final movie = (api.posted.single['TypeOptions'] as List).single as Map;
    expect(movie['ImageOptions'], [
      {'Type': 'Primary', 'Limit': 1, 'MinWidth': 0},
      {'Type': 'Logo', 'Limit': 1, 'MinWidth': 0},
      {'Type': 'Thumb', 'Limit': 1, 'MinWidth': 0},
      {'Type': 'Backdrop', 'Limit': 3, 'MinWidth': 1280},
    ]);
  });

  // Posting the PathInfos loaded before a path change would make the server
  // recreate a removed folder and drop an added one.
  testWidgets('a path add reloads, and save posts the server paths', (
    tester,
  ) async {
    await setUpServer();
    await pump(tester);
    await openTab(tester, l10n.adminLibraryTabOptions);
    await tester.tap(find.text(l10n.adminLibRealtimeMonitor));
    await tester.pump();

    await addPath(tester, '/media/more');

    expect(api.calls, ['add Main /media/more refresh=true']);
    expect(find.text('/media/more'), findsOneWidget);
    final draft = AdminDraft.active.value!;
    expect(draft.isDirty, isTrue, reason: 'the unsaved switch survives');

    await draft.save();
    final body = api.posted.single;
    expect(body['PathInfos'], [
      {'Path': '/media/main'},
      {'Path': '/media/more'},
    ]);
    expect(body['EnableRealtimeMonitor'], isTrue);
  });

  testWidgets('a path change alone leaves nothing to save', (tester) async {
    await setUpServer();
    await pump(tester);
    await openTab(tester, l10n.adminLibraryTabPaths);

    await tester.tap(find.byTooltip(l10n.adminRemovePath));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.remove).last);
    await tester.pumpAndSettle();

    expect(api.calls, ['remove Main /media/main refresh=true']);
    expect(AdminDraft.active.value!.isDirty, isFalse);
    expect(find.text(l10n.adminNoMediaPaths), findsOneWidget);
  });

  testWidgets('a movies library shows its options and refresh presets', (
    tester,
  ) async {
    await setUpServer();
    await pump(tester);
    await openTab(tester, l10n.adminLibraryTabOptions);

    expect(find.text(l10n.adminLibEnableLibrary), findsOneWidget);
    expect(find.text(l10n.adminLibTrickplayExtraction), findsOneWidget);
    expect(find.text(l10n.adminLibAutoAddToCollection), findsOneWidget);
    expect(find.text(l10n.adminLibLufsScan), findsNothing);
    // Extras titles show only while embedded titles are on.
    expect(find.text(l10n.adminLibEmbeddedExtrasTitles), findsNothing);
    await tester.tap(find.text(l10n.adminLibEmbeddedTitles));
    await tester.pump();
    expect(find.text(l10n.adminLibEmbeddedExtrasTitles), findsOneWidget);

    await tester.tap(find.text(l10n.adminLibRefreshNever));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminLibRefreshDays(90)).last, findsOneWidget);
    expect(find.text(l10n.adminLibRefreshDays(120)), findsNothing);
  });

  testWidgets('a music library edits its tag delimiters as characters', (
    tester,
  ) async {
    await setUpServer(type: 'music');
    await pump(tester);
    await openTab(tester, l10n.adminLibraryTabOptions);

    expect(find.text(l10n.adminLibTrickplayExtraction), findsNothing);
    expect(find.text(l10n.adminLibrarySectionSubtitles), findsNothing);
    final delimiters = find.descendant(
      of: find.ancestor(
        of: find.text(l10n.adminLibCustomTagDelimiters),
        matching: find.byType(Padding),
      ).first,
      matching: find.byType(EditableText),
    );
    await tester.enterText(delimiters, ';|');
    await tester.tap(find.text(l10n.adminLibSaveLyricsWithMedia));
    await tester.pump();

    await AdminDraft.active.value!.save();
    expect(api.posted.single['CustomTagDelimiters'], [';', '|']);
    expect(api.posted.single['SaveLyricsWithMedia'], isTrue);
  });

  testWidgets('a collections library has no folders tab', (tester) async {
    await setUpServer(type: 'boxsets');
    await pump(tester);

    expect(find.text(l10n.adminLibraryTabPaths), findsNothing);
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await setUpServer();
    await pump(tester);
    await openTab(tester, l10n.adminLibraryTabOptions);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });

  group('on Emby', () {
    // An Emby 4.9 series library's options, trimmed.
    Map<String, dynamic> embyOptions() => {
          'EnablePhotos': true,
          'EnableRealtimeMonitor': true,
          'EnableMarkerDetection': false,
          'EnableMarkerDetectionDuringLibraryScan': false,
          'EnableChapterImageExtraction': false,
          'ExtractChapterImagesDuringLibraryScan': false,
          'ExcludeFromSearch': false,
          'PathInfos': [
            {'Path': '/media/main'},
          ],
          'SaveLocalMetadata': false,
          'SaveLocalThumbnailSets': false,
          'ImportPlaylists': true,
          'EnableAutomaticSeriesGrouping': true,
          'EnableEmbeddedTitles': false,
          'AutomaticRefreshIntervalDays': 0,
          'ContentType': 'tvshows',
          'DisabledLyricsFetchers': [],
          'LyricsFetcherOrder': [],
          'SaveLyricsWithMedia': true,
          'SubtitleDownloadLanguages': [],
          'ForcedSubtitlesOnly': false,
          'RequirePerfectSubtitleMatch': true,
          'SaveSubtitlesWithMedia': true,
          'TypeOptions': [],
          'ImportCollections': false,
          'MinResumePct': 2,
          'MaxResumePct': 90,
          'MinResumeDurationSeconds': 120,
          'ThumbnailImagesIntervalSeconds': -1,
        };

    Finder textField(String label) => find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Padding))
              .first,
          matching: find.byType(EditableText),
        );

    testWidgets('a series library shows Emby rows and saves them', (
      tester,
    ) async {
      await setUpServer(type: 'tvshows');
      api.options = embyOptions();
      await pump(tester, onEmby: true);
      await openTab(tester, l10n.adminLibraryTabOptions);

      for (final label in [
        l10n.adminLibEnableLibrary,
        l10n.adminLibTrickplayExtraction,
        l10n.adminLibEmbeddedEpisodeInfos,
        l10n.adminLibAllowEmbeddedSubtitles,
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text(l10n.adminLibImportPlaylists), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.adminLibIntroDetection));
      await tester.tap(find.text(l10n.adminLibIntroDetection));
      await tester.pump();
      await tester.ensureVisible(find.text(l10n.adminLibThumbnailAtChapters));
      await tester.tap(find.text(l10n.adminLibThumbnailAtChapters));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.adminLibThumbnailEverySeconds(10)).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(textField(l10n.adminResumeMinPct));
      await tester.enterText(textField(l10n.adminResumeMinPct), '5');
      // A blank entry keeps the stored value.
      await tester.enterText(textField(l10n.adminResumeMaxPct), '');
      await tester.pump();

      expect(await AdminDraft.active.value!.save(), isTrue);
      final posted = api.posted.single;
      expect(posted['EnableMarkerDetection'], isTrue);
      expect(posted['ThumbnailImagesIntervalSeconds'], 10);
      expect(posted['MinResumePct'], 5);
      expect(posted['MaxResumePct'], 90);
      expect(posted.containsKey('Enabled'), isFalse);
      expect(posted.containsKey('EnableTrickplayImageExtraction'), isFalse);
    });

    testWidgets('a movies library imports collections, with no intro markers', (
      tester,
    ) async {
      await setUpServer();
      api.options = embyOptions()..['ContentType'] = 'movies';
      await pump(tester, onEmby: true);
      await openTab(tester, l10n.adminLibraryTabOptions);

      expect(find.text(l10n.adminLibIntroDetection), findsNothing);
      expect(find.text(l10n.adminLibAutoAddToCollection), findsNothing);
      await tester.ensureVisible(find.text(l10n.adminLibImportCollections));
      await tester.tap(find.text(l10n.adminLibImportCollections));
      await tester.pump();

      expect(await AdminDraft.active.value!.save(), isTrue);
      expect(api.posted.single['ImportCollections'], isTrue);
      expect(api.posted.single.containsKey('AutomaticallyAddToCollection'),
          isFalse);
    });

    testWidgets('a music library lists Emby lyric downloaders', (tester) async {
      await setUpServer(type: 'music');
      api.options = embyOptions()..['ContentType'] = 'music';
      api.availableExtras = {
        'LyricsFetchers': [
          {'Name': 'Lyrics Finder', 'DefaultEnabled': true},
        ],
      };
      await pump(tester, onEmby: true);
      await openTab(tester, l10n.adminLibraryTabOptions);
      expect(find.text(l10n.adminLibLufsScan), findsNothing);
      expect(find.text(l10n.adminLibCustomTagDelimiters), findsNothing);

      await openTab(tester, l10n.adminLibraryTabDownloaders);
      expect(find.text(l10n.adminLibLyricDownloaders.toUpperCase()),
          findsOneWidget);
      await tester.tap(find.descendant(
        of: find.widgetWithText(Row, 'Lyrics Finder').last,
        matching: find.byType(Checkbox),
      ));
      await tester.pump();

      expect(await AdminDraft.active.value!.save(), isTrue);
      expect(api.posted.single['DisabledLyricsFetchers'], ['Lyrics Finder']);
      expect(api.posted.single['LyricsFetcherOrder'], ['Lyrics Finder']);
    });
  });
}
