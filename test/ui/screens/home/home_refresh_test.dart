import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/multi_server_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/preference/home_section_config.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/home_refresh_bus.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDataSource extends Mock implements RowDataSource {}

class _MockClient extends Mock implements MediaServerClient {}

class _MockMediaBar extends Mock implements MediaBarViewModel {}

class _MockMultiServer extends Mock implements MultiServerRepository {}

class _MockSync extends Mock implements PluginSyncService {}

class _MockSeerrPrefs extends Mock implements SeerrPreferences {}

// Issue #1332: a Home tap or a pull down refreshes Home with a new media bar
// set, while the refreshes that run on their own keep the current one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only a Home tap asks for a new media bar, and only once', () {
    final bus = HomeRefreshBus();
    bus.request();
    expect(bus.consumeNewMediaBar(), isFalse);

    bus.request(newMediaBar: true);
    expect(bus.consumeNewMediaBar(), isTrue);
    expect(bus.consumeNewMediaBar(), isFalse);
  });

  group('HomeViewModel.refresh', () {
    late _MockMediaBar mediaBar;
    late HomeViewModel model;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.setHomeSectionsConfig([
        for (final config in HomeSectionConfig.defaults())
          config.copyWith(enabled: false),
      ]);
      await prefs.set(
        UserPreferences.lastExternalRowsRefreshTime,
        DateTime.now().millisecondsSinceEpoch,
      );

      final sync = _MockSync();
      when(() => sync.seerrAvailable).thenReturn(false);
      when(() => sync.pluginAvailable).thenReturn(false);
      GetIt.instance.registerSingleton<PluginSyncService>(sync);
      GetIt.instance.registerSingleton<SeerrPreferences>(_MockSeerrPrefs());

      final client = _MockClient();
      when(() => client.userId).thenReturn('user');
      when(() => client.baseUrl).thenReturn('http://server.test');
      mediaBar = _MockMediaBar();
      when(
        () => mediaBar.load(force: any(named: 'force')),
      ).thenAnswer((_) async {});
      model = HomeViewModel(
        dataSource: _MockDataSource(),
        prefs: prefs,
        client: client,
        mediaBarViewModel: mediaBar,
        multiServerRepo: _MockMultiServer(),
      );
    });

    tearDown(() async {
      model.dispose();
      debugDefaultTargetPlatformOverride = null;
      await GetIt.instance.reset();
    });

    test('keeps the media bar set by default', () async {
      await model.refresh();
      verifyNever(() => mediaBar.load(force: true));
    });

    test('loads a new media bar set when asked', () async {
      await model.refresh(newMediaBar: true);
      verify(() => mediaBar.load(force: true)).called(1);
    });
  });
}
