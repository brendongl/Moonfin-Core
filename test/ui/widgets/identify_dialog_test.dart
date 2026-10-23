import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/identify_dialog.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeItemsApi extends Fake implements ItemsApi {
  Map<String, dynamic> item = {'Id': 'm1', 'Type': 'Movie', 'Name': 'Alien'};

  @override
  Future<Map<String, dynamic>> getItem(
    String itemId, {
    String? mediaSourceId,
    String? fields,
  }) async => Map<String, dynamic>.from(item);
}

class _FakeAdminItemsApi extends Fake implements AdminItemsApi {
  final searches = <Map<String, dynamic>>[];
  // A 12.1 server with the anime plugins, as GET /Items/{id}/ExternalIdInfos
  // answers for a movie.
  List<Map<String, dynamic>> idInfos = [
    {'Name': 'AniDB', 'Key': 'AniDB'},
    {'Name': 'IMDb', 'Key': 'Imdb'},
    {'Name': 'TheMovieDb', 'Key': 'Tmdb', 'Type': 'Movie'},
    {'Name': 'TheMovieDb', 'Key': 'TmdbCollection', 'Type': 'BoxSet'},
  ];

  @override
  Future<List<Map<String, dynamic>>> getExternalIdInfos(String itemId) async =>
      idInfos;

  @override
  Future<List<Map<String, dynamic>>> searchRemote(
    String searchType,
    Map<String, dynamic> query,
  ) async {
    searches.add(query);
    return const [];
  }
}

void main() {
  late _FakeItemsApi items;
  late _FakeAdminItemsApi admin;
  late AppLocalizations l10n;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    items = _FakeItemsApi();
    admin = _FakeAdminItemsApi();
    final client = _MockMediaServerClient();
    when(() => client.itemsApi).thenReturn(items);
    when(() => client.adminItemsApi).thenReturn(admin);
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async => GetIt.instance.reset());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => IdentifyDialog.show(
                context,
                itemId: 'm1',
                itemType: 'Movie',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a locked item is refused', (tester) async {
    items.item = {...items.item, 'LockData': true};
    await open(tester);

    expect(find.text(l10n.adminMetadataItemLocked), findsOneWidget);
    expect(find.byType(IdentifyDialog), findsNothing);
  });

  // One "{name} {type} Id" row per ExternalIdInfos entry, and each filled row
  // goes out under its key.
  testWidgets('the id rows come from the server, plugins included', (
    tester,
  ) async {
    items.item = {
      ...items.item,
      'ProviderIds': {'tmdb': '348'},
    };
    await open(tester);

    expect(find.text(l10n.adminExternalIdLabel('AniDB')), findsOneWidget);
    expect(
      find.text(l10n.adminExternalIdLabel('TheMovieDb ${l10n.collection}')),
      findsOneWidget,
    );
    // The current value, matched to the key without regard to case.
    expect(find.text('348'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, l10n.adminExternalIdLabel('AniDB')),
      '1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.adminExternalIdLabel('IMDb')),
      '78748',
    );
    await tester.tap(find.text(l10n.search).last);
    await tester.pumpAndSettle();

    expect(admin.searches.first['SearchInfo']['ProviderIds'], {
      'AniDB': '1',
      'Imdb': 'tt78748',
    });
  });

  // The rows arrive with the server's answer, so the d-pad walk has to reach
  // every one of them and still end on the buttons.
  testWidgets('on TV the d-pad walks every id row to the buttons', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    await open(tester);

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    // A focused TV field blinks its caret, so settling never ends.
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 300));
    }

    tester
        .widget<Focus>(find.byWidgetPredicate((w) =>
            w is Focus && w.focusNode?.debugLabel == 'identify-close-btn'))
        .focusNode!
        .requestFocus();
    await tester.pump();

    // Name, year and the four ids from the server.
    for (var i = 0; i < 6; i++) {
      await press(LogicalKeyboardKey.arrowDown);
      expect(focused(), 'identify-field-$i');
    }
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'identify-cancel-btn');
    await press(LogicalKeyboardKey.arrowUp);
    expect(focused(), 'identify-field-5');

    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'identify-search-btn');
    await press(LogicalKeyboardKey.arrowUp);
    expect(focused(), 'identify-arrow-5');
  });

  testWidgets('a search needs a name or an id', (tester) async {
    await open(tester);

    await tester.tap(find.text(l10n.search).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminMetadataNameOrIdRequired), findsOneWidget);
    expect(admin.searches, isEmpty);
  });
}
