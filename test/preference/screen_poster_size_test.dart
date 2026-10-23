import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UserPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({
    'pref_last_server_id': 'server1',
    'pref_last_user_id': 'user1',
  });
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screens = {
    'favorites': UserPreferences.favoritesPosterSize,
    'all genres': UserPreferences.allGenresPosterSize,
    'seerr': UserPreferences.seerrPosterSize,
  };

  for (final MapEntry(key: name, value: preference) in screens.entries) {
    group('$name poster size', () {
      test('follows the library size until it is picked', () async {
        final prefs = await _prefs();
        await prefs.set(UserPreferences.libraryPosterSize, PosterSize.large);

        expect(prefs.resolveScreenPosterSize(preference), PosterSize.large);
      });

      test('a pick there leaves the library size alone', () async {
        final prefs = await _prefs();
        await prefs.set(UserPreferences.libraryPosterSize, PosterSize.large);
        await prefs.set(preference, PosterSize.small);

        expect(prefs.resolveScreenPosterSize(preference), PosterSize.small);
        expect(prefs.resolveLibraryPosterSize(), PosterSize.large);

        await prefs.set(UserPreferences.libraryPosterSize, PosterSize.medium);
        expect(prefs.resolveScreenPosterSize(preference), PosterSize.small);
      });
    });
  }
}
