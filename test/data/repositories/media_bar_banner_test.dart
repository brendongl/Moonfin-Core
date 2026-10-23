import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/media_bar_repository.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _ImageApi extends Mock implements ImageApi {}

// Issue #1265: a slide carries the item's banner art when the server has it.
void main() {
  test('a banner tag becomes the slide banner, and none leaves it unset', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();

    final items = _ItemsApi();
    when(
      () => items.getItems(
        includeItemTypes: any(named: 'includeItemTypes'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {
            'Id': 'show',
            'Name': 'The Show',
            'ImageTags': {'Banner': 'b1', 'Primary': 'p1'},
          },
          {
            'Id': 'film',
            'Name': 'The Film',
            'ImageTags': {'Primary': 'p2'},
          },
        ],
      },
    );
    final images = _ImageApi();
    when(
      () => images.getBannerImageUrl(
        any(),
        tag: any(named: 'tag'),
        maxWidth: any(named: 'maxWidth'),
      ),
    ).thenAnswer(
      (call) =>
          'banner/${call.positionalArguments.first}/${call.namedArguments[#tag]}',
    );
    when(
      () => images.getPrimaryImageUrl(
        any(),
        tag: any(named: 'tag'),
        maxWidth: any(named: 'maxWidth'),
      ),
    ).thenReturn('primary');
    final client = _Client();
    when(() => client.itemsApi).thenReturn(items);
    when(() => client.imageApi).thenReturn(images);

    final slides = await MediaBarRepository(
      client,
      UserPreferences(store),
    ).fetchPreviewItems();

    expect(slides.map((s) => s.bannerUrl), ['banner/show/b1', null]);
  });
}
