import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/metadata/admin_metadata_edit_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeItemsApi extends Fake implements ItemsApi {
  Map<String, dynamic> item = {
    'Id': 'm1',
    'Type': 'Movie',
    'MediaType': 'Video',
    'Name': 'Alien',
    'SortName': 'alien',
    'OriginalLanguage': 'en',
    'CommunityRating': 8.5,
    'CriticRating': 90,
    'ProductionYear': 1979,
    'PremiereDate': '1979-05-25T04:00:00.0000000Z',
    'ProviderIds': {'Imdb': 'tt0078748', 'Tmdb': '348', 'PluginX': 'abc'},
    'Genres': ['Horror'],
    'Tags': <String>[],
    'Studios': [
      {'Name': 'Brandywine', 'Id': 's1'},
    ],
    'People': [
      {'Name': 'Sigourney Weaver', 'Role': 'Ripley', 'Type': 'Actor', 'Id': 'p1'},
    ],
    'LockData': false,
    'LockedFields': <String>[],
    'Taglines': ['In space no one can hear you scream.'],
    'Overview': 'A crew answers a distress call.',
    'UserData': {'Played': true},
    'ImageTags': {'Primary': 'tag1'},
  };

  @override
  Future<Map<String, dynamic>> getItem(
    String itemId, {
    String? mediaSourceId,
    String? fields,
  }) async => Map<String, dynamic>.from(item);
}

class _FakeAdminItemsApi extends Fake implements AdminItemsApi {
  Map<String, dynamic> editor = {
    'ExternalIdInfos': [
      {'Key': 'Imdb', 'Name': 'IMDb'},
      {'Key': 'Tmdb', 'Name': 'TheMovieDb'},
    ],
    'ContentType': 'movies',
    'ContentTypeOptions': [
      {'Name': 'Inherit', 'Value': ''},
      {'Name': 'Movies', 'Value': 'movies'},
    ],
    'Cultures': [
      {'DisplayName': 'English', 'TwoLetterISOLanguageName': 'en'},
      {'DisplayName': 'French', 'TwoLetterISOLanguageName': 'fr'},
    ],
    'Countries': <Map<String, dynamic>>[],
    'ParentalRatingOptions': [
      {'Name': 'R'},
    ],
  };
  final updates = <Map<String, dynamic>>[];
  final contentTypes = <String>[];
  final refreshes = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> getMetadataEditor(String itemId) async =>
      editor;

  @override
  Future<void> updateItem(String itemId, Map<String, dynamic> itemData) async {
    expect(itemId, 'm1');
    updates.add(itemData);
  }

  @override
  Future<void> updateContentType(String itemId, String contentType) async =>
      contentTypes.add(contentType);

  @override
  Future<void> refreshItem(
    String itemId, {
    bool? recursive,
    bool? replaceAllMetadata,
    bool? replaceAllImages,
    bool? regenerateTrickplay,
    MetadataRefreshMode metadataRefreshMode = MetadataRefreshMode.defaultRefresh,
    MetadataRefreshMode imageRefreshMode = MetadataRefreshMode.defaultRefresh,
  }) async {
    refreshes.add({
      'MetadataRefreshMode': metadataRefreshMode.toServerString(),
      'ReplaceAllMetadata': replaceAllMetadata,
    });
  }
}

class _FakeImageApi extends Fake implements ImageApi {
  @override
  String getPrimaryImageUrl(String itemId,
          {int? maxWidth, int? maxHeight, String? tag}) =>
      '';

  @override
  String getBackdropImageUrl(String itemId,
          {int? maxWidth, int? index, String? tag}) =>
      '';

  @override
  String getLogoImageUrl(String itemId, {int? maxWidth, String? tag}) => '';

  @override
  String getBannerImageUrl(String itemId, {int? maxWidth, String? tag}) => '';

  @override
  String getThumbImageUrl(String itemId, {int? maxWidth, String? tag}) => '';
}

void main() {
  late _FakeItemsApi items;
  late _FakeAdminItemsApi admin;
  late AppLocalizations l10n;

  setUp(() async {
    items = _FakeItemsApi();
    admin = _FakeAdminItemsApi();
    final client = _MockMediaServerClient();
    when(() => client.itemsApi).thenReturn(items);
    when(() => client.adminItemsApi).thenReturn(admin);
    when(() => client.imageApi).thenReturn(_FakeImageApi());
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(
    WidgetTester tester, {
    ServerType server = ServerType.jellyfin,
  }) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminServerScope(
          serverType: server,
          child: const Scaffold(body: AdminMetadataEditScreen(itemId: 'm1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Padding)).first,
    matching: find.byType(EditableText),
  );

  testWidgets('save sends the editor fields over a fresh copy of the item', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(field(l10n.adminMetadataFieldTitle), 'Alien (1979)');
    await tester.enterText(field(l10n.adminMetadataFieldCommunityRating), '');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('French').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminMetadataExternalIds).first);
    await tester.pumpAndSettle();
    await tester.enterText(field(l10n.adminExternalIdLabel('IMDb')), 'tt1');
    await tester.pump();

    // Someone else edited the overview after the page loaded.
    items.item = {...items.item, 'Overview': 'Changed elsewhere.'};
    expect(await AdminDraft.active.value!.save(), isTrue);

    final body = admin.updates.single;
    expect(body['Name'], 'Alien (1979)');
    expect(body['OriginalLanguage'], 'fr');
    expect(body['CommunityRating'], isNull, reason: 'an empty field clears it');
    expect(body.containsKey('CommunityRating'), isTrue);
    expect(body['Overview'], 'Changed elsewhere.');
    expect(body['ProviderIds'], {'Imdb': 'tt1', 'Tmdb': '348', 'PluginX': 'abc'});
    expect(body.containsKey('UserData'), isFalse);
    expect(body.containsKey('SortName'), isFalse);
  });

  // The server clears OriginalLanguage when the body leaves it out, SortName
  // is computed and mustn't come back as ForcedSortName, and provider ids the
  // server doesn't list must survive.
  testWidgets('a title edit leaves the other stored values alone', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(field(l10n.adminMetadataFieldTitle), 'Alien');
    await tester.enterText(field(l10n.adminMetadataFieldTitle), 'Alien!');
    await tester.pump();
    await AdminDraft.active.value!.save();

    final body = admin.updates.single;
    expect(body['OriginalLanguage'], 'en');
    expect(body.containsKey('ForcedSortName'), isFalse);
    expect(body['ProviderIds']['PluginX'], 'abc');
    expect(body['PremiereDate'], '1979-05-25T04:00:00.0000000Z');
    expect(body['People'], items.item['People']);
  });

  testWidgets('the sort title field edits the forced sort name only', (
    tester,
  ) async {
    await pump(tester);

    final sortTitle = field(l10n.adminMetadataFieldSortTitle);
    expect(tester.widget<EditableText>(sortTitle).controller.text, isEmpty);
    await tester.enterText(sortTitle, 'Alien 1');
    await tester.pump();
    await AdminDraft.active.value!.save();

    expect(admin.updates.single['ForcedSortName'], 'Alien 1');
  });

  testWidgets('the content type can go back to Inherit', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminContentType));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movies').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inherit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminMetadataUpdate));
    await tester.pumpAndSettle();

    expect(admin.contentTypes, ['']);
  });

  testWidgets('no content type action when the server offers none', (
    tester,
  ) async {
    admin.editor = {...admin.editor, 'ContentTypeOptions': const []};
    await pump(tester);

    expect(find.text(l10n.adminContentType), findsNothing);
  });

  testWidgets('Emby has no content type action', (tester) async {
    await pump(tester, server: ServerType.emby);
    expect(find.text(l10n.adminContentType), findsNothing);
  });

  testWidgets('refresh sends the picked mode', (tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, l10n.refresh));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminRefreshModeScan));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminRefreshModeMissing).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.refresh).last);
    await tester.pumpAndSettle();

    expect(admin.refreshes.single, {
      'MetadataRefreshMode': 'FullRefresh',
      'ReplaceAllMetadata': false,
    });
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
