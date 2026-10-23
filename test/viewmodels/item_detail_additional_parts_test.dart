import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/modern/modern_detail_content.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _PluginSyncService extends Mock implements PluginSyncService {}

void main() {
  late _Client client;
  late _ItemsApi itemsApi;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    final pluginSync = _PluginSyncService();
    when(() => pluginSync.seerrAvailable).thenReturn(false);
    GetIt.instance.registerSingleton<PluginSyncService>(pluginSync);

    client = _Client();
    itemsApi = _ItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('http://server');

    when(() => itemsApi.getSpecialFeatures('movie-1')).thenAnswer(
      (_) async => [
        {'Id': 'bts', 'Type': 'Video', 'ExtraType': 'BehindTheScenes'},
      ],
    );
    when(() => itemsApi.getAdditionalParts('movie-1')).thenAnswer(
      (_) async => [
        {'Id': 'part-2', 'Type': 'Video', 'Name': 'DVD2'},
      ],
    );
  });

  tearDown(() => GetIt.instance.reset());

  Future<ItemDetailViewModel> loadMovie(Map<String, dynamic> data) async {
    when(
      () => itemsApi.getItem(
        'movie-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer((_) async => data);
    final tmdb = TmdbRepository(client);
    final vm = ItemDetailViewModel(
      itemId: 'movie-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    );
    await vm.load();
    // load() starts the extras without waiting for them, so give them a moment.
    for (var i = 0; i < 100 && vm.features.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return vm;
  }

  test('a multi-part movie lists its other parts first, under their own heading',
      () async {
    final vm = await loadMovie(
      {'Id': 'movie-1', 'Type': 'Movie', 'Name': 'Metallica', 'PartCount': 2},
    );

    expect(vm.features.map((f) => f.id), ['part-2', 'bts']);
    expect(vm.features.map(getExtraCategory), [
      'additionalParts',
      'behindTheScenes',
    ]);
  });

  test('a single-file movie never asks for parts', () async {
    final vm = await loadMovie(
      {'Id': 'movie-1', 'Type': 'Movie', 'Name': 'Metallica'},
    );

    expect(vm.features.map((f) => f.id), ['bts']);
    verifyNever(() => itemsApi.getAdditionalParts(any()));
  });
}
