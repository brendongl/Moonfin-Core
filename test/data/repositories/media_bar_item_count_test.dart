import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/media_bar_state.dart';
import 'package:moonfin/data/repositories/media_bar_repository.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _ImageApi extends Mock implements ImageApi {}

class _UserViewsApi extends Mock implements UserViewsApi {}

// Issue #1881: the Item Count setting holds with plugin sync off.
void main() {
  tearDown(() => GetIt.instance.reset());

  test('a picked count is shown without plugin sync', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);
    await prefs.set(UserPreferences.pluginSyncEnabled, false);
    await prefs.set(UserPreferences.mediaBarItemCount, '30');
    // Recently added is a single request, which keeps the fakes small.
    await prefs.set(
      UserPreferences.mediaBarSourceType,
      UserPreferences.mediaBarSourceRecentlyAdded,
    );

    final views = _UserViewsApi();
    when(() => views.getUserViews()).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'lib', 'Name': 'Movies', 'CollectionType': 'movies'},
        ],
      },
    );
    final items = _ItemsApi();
    when(
      () => items.getLatestItems(
        parentId: any(named: 'parentId'),
        includeItemTypes: any(named: 'includeItemTypes'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          for (var i = 0; i < 40; i++)
            {
              'Id': 'm$i',
              'BackdropImageTags': ['b$i'],
            },
        ],
      },
    );
    final images = _ImageApi();
    when(
      () => images.getBackdropImageUrl(
        any(),
        tag: any(named: 'tag'),
        maxWidth: any(named: 'maxWidth'),
      ),
    ).thenReturn('backdrop');
    when(
      () => images.getPrimaryImageUrl(
        any(),
        tag: any(named: 'tag'),
        maxWidth: any(named: 'maxWidth'),
      ),
    ).thenReturn('primary');
    final client = _Client();
    when(() => client.userViewsApi).thenReturn(views);
    when(() => client.itemsApi).thenReturn(items);
    when(() => client.imageApi).thenReturn(images);

    final repo = MediaBarRepository(client, prefs);
    GetIt.instance.registerSingleton<MediaBarRepository>(repo);

    final state = await repo.loadItems();

    expect((state as MediaBarReady).items, hasLength(30));
  });
}
