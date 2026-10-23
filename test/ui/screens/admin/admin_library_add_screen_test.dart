import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/libraries/admin_library_add_screen.dart';
import 'package:moonfin/ui/screens/admin/libraries/library_options_defaults.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeLibraryApi extends Fake implements AdminLibraryApi {
  final availableFor = <String?>[];
  final created = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getAvailableLibraryOptions(
    String? contentType,
  ) async {
    availableFor.add(contentType);
    return {
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
            {'Name': 'The Open Movie Database', 'DefaultEnabled': false},
          ],
          'ImageFetchers': [],
          'SimilarItemProviders': [
            {'Name': 'Local Genre/Tag', 'DefaultEnabled': true},
          ],
        },
      ],
    };
  }

  @override
  Future<void> addVirtualFolder({
    required String name,
    String? collectionType,
    List<String>? paths,
    Map<String, dynamic>? libraryOptions,
    bool refreshLibrary = false,
  }) async {
    created.add({
      'name': name,
      'collectionType': collectionType,
      'paths': paths,
      'libraryOptions': libraryOptions,
      'refreshLibrary': refreshLibrary,
    });
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

  setUp(() async {
    api = _FakeLibraryApi();
    final client = _MockMediaServerClient();
    when(() => client.adminLibraryApi).thenReturn(api);
    when(() => client.adminEnvironmentApi).thenReturn(_FakeEnvironmentApi());
    when(() => client.adminSystemApi).thenReturn(_FakeSystemApi());
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('libraries')),
          routes: [
            GoRoute(
              path: 'add',
              builder: (_, _) =>
                  const Scaffold(body: AdminLibraryAddScreen()),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    router.push('/add');
    await tester.pumpAndSettle();
  }

  Future<void> addFolder(WidgetTester tester, String path) async {
    await tester.enterText(find.widgetWithText(TextField, l10n.path), path);
    await tester.tap(find.text(l10n.select));
    await tester.pumpAndSettle();
  }

  FilledButton nextButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10n.next));

  testWidgets('photos is not a type the server can create', (tester) async {
    await pump(tester);

    expect(find.text(l10n.photos), findsNothing);
    expect(find.text(l10n.homeVideosAndPhotos), findsOneWidget);
  });

  testWidgets('a library needs a folder before it can be created', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.movies));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();

    expect(nextButton(tester).onPressed, isNull);
    await addFolder(tester, '/media/movies');
    expect(nextButton(tester).onPressed, isNotNull);
  });

  testWidgets('create sends the default options with the folders', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.movies));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await addFolder(tester, '/media/movies');
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminCreateLibrary));
    await tester.pumpAndSettle();

    expect(api.availableFor, ['movies']);
    final call = api.created.single;
    expect(call['name'], l10n.movies);
    expect(call['collectionType'], 'movies');
    expect(call['paths'], ['/media/movies']);
    expect(call['refreshLibrary'], isTrue);
    final options = call['libraryOptions'] as Map<String, dynamic>;
    expect(options['Enabled'], isTrue);
    expect(options['EnableRealtimeMonitor'], isTrue);
    expect(options['SaveSubtitlesWithMedia'], isTrue);
    expect(options['RequirePerfectSubtitleMatch'], isTrue);
    expect(options['SeasonZeroDisplayName'], 'Specials');
    expect(options['CustomTagDelimiters'], ['/', '|', ';', r'\']);
    expect(options.containsKey('EnableArchiveMediaFiles'), isFalse);
    expect(options['MetadataSavers'], ['Nfo']);
    expect(options['LocalMetadataReaderOrder'], ['Nfo']);
    expect(options['TypeOptions'], [
      {
        'Type': 'Movie',
        'MetadataFetcherOrder': ['TheMovieDb', 'The Open Movie Database'],
        'MetadataFetchers': ['TheMovieDb'],
        'SimilarItemProviderOrder': ['Local Genre/Tag'],
        'SimilarItemProviders': ['Local Genre/Tag'],
      },
    ]);
    expect(find.text('libraries'), findsOneWidget);
  });

  testWidgets('a mixed library is sent with no type', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.mixedMoviesAndShows));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await addFolder(tester, '/media/mixed');
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminCreateLibrary));
    await tester.pumpAndSettle();

    expect(api.availableFor, [null]);
    expect(api.created.single['collectionType'], isNull);
  });

  testWidgets('the options step edits what the library is created with', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.movies));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await addFolder(tester, '/media/movies');
    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.adminLibRealtimeMonitor));
    await tester.pumpAndSettle();
    // Tick The Open Movie Database, the second Movie downloader.
    final omdb = find.ancestor(
      of: find.text('The Open Movie Database'),
      matching: find.byType(Row),
    );
    await tester.ensureVisible(omdb.first);
    await tester.tap(
      find.descendant(of: omdb.first, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminCreateLibrary));
    await tester.pumpAndSettle();

    final options = api.created.single['libraryOptions'] as Map<String, dynamic>;
    expect(options['EnableRealtimeMonitor'], isFalse);
    expect(
      (options['TypeOptions'] as List).single['MetadataFetchers'],
      ['TheMovieDb', 'The Open Movie Database'],
    );
  });

  test('Emby starts a new library from its own defaults', () {
    final options = newLibraryOptions({
      'LyricsFetchers': [
        {'Name': 'Lyrics Finder', 'DefaultEnabled': false},
      ],
      'TypeOptions': const [],
      'DefaultLibraryOptions': {
        'EnableRealtimeMonitor': true,
        'MinResumePct': 2,
        'ThumbnailImagesIntervalSeconds': -1,
        'PathInfos': const [],
        'TypeOptions': const [],
      },
    });
    expect(options['MinResumePct'], 2);
    expect(options['ThumbnailImagesIntervalSeconds'], -1);
    expect(options['LyricsFetcherOrder'], ['Lyrics Finder']);
    expect(options['DisabledLyricsFetchers'], ['Lyrics Finder']);
    // None of Jellyfin's defaults.
    expect(options.containsKey('Enabled'), isFalse);
    expect(options.containsKey('EnableTrickplayImageExtraction'), isFalse);
  });
}
