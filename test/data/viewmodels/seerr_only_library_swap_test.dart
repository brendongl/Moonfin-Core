import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Seerr server whose answer for the title can be changed between refreshes.
class _FakeSeerr extends Fake implements SeerrRepository {
  SeerrMediaInfo mediaInfo = const SeerrMediaInfo(status: 3);

  SeerrMovieDetails get _details => SeerrMovieDetails(
    id: 299534,
    title: 'Avengers: Endgame',
    mediaInfo: mediaInfo,
  );

  @override
  Future<void> ensureInitialized({bool force = false}) async {}

  @override
  Future<Map<String, dynamic>> getPublicSettings() async => const {};

  @override
  Future<SeerrUser> getCurrentUser() async => SeerrUser(id: 1);

  @override
  Future<(SeerrMovieDetails, bool)> getMovieDetailsWithWatchlist(
    int tmdbId,
  ) async => (_details, false);

  @override
  Future<SeerrMovieDetails> getMovieDetails(int tmdbId) async => _details;
}

class _FakePrefs extends Fake implements SeerrPreferences {}

class _Client extends Mock implements MediaServerClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSeerr seerr;
  late _Client client;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    seerr = _FakeSeerr();
    // Registered the way the app does, since the view model reaches it with
    // getAsync.
    GetIt.instance.registerLazySingletonAsync<SeerrRepository>(
      () async => seerr,
    );
    GetIt.instance.registerSingleton<SeerrPreferences>(_FakePrefs());
    client = _Client();
  });

  tearDown(() => GetIt.instance.reset());

  test('a title that lands while its page is open swaps it out', () {
    fakeAsync((async) {
      final tmdb = TmdbRepository(client);
      final vm = ItemDetailViewModel(
        itemId: 'tmdb:movie:299534',
        client: client,
        mutations: ItemMutationRepository(client),
        mdbListRepository: MdbListRepository(client, tmdb),
        tmdbRepository: tmdb,
      );
      vm.load();
      async.flushMicrotasks();
      expect(vm.isSeerrOnly, isTrue);
      expect(vm.seerrResolvedLibraryId, isNull);

      seerr.mediaInfo = const SeerrMediaInfo(
        status: 5,
        jellyfinMediaId: 'library-item',
      );
      async.elapse(const Duration(seconds: 30));
      expect(vm.seerrResolvedLibraryId, 'library-item');

      vm.dispose();
    });
  });
}
