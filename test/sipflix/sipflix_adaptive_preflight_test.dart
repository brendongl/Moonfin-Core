import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/sipflix/sipflix_preflight.dart';
import 'package:moonfin/sipflix/sipflix_route_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool run({
    bool manual = false,
    bool adaptive = true,
    bool emby = true,
    int routes = 3,
    bool uncertain = true,
  }) => SipflixPreflightController.shouldRun(
    manualEveryPlay: manual,
    adaptiveEnabled: adaptive,
    isEmby: emby,
    routeCount: routes,
    uncertain: uncertain,
  );

  test(
    'adaptive checks default on without changing explicit every-play default',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      expect(prefs.get(UserPreferences.adaptivePreflightEnabled), isTrue);
      expect(prefs.get(UserPreferences.preflightEnabled), isFalse);
    },
  );
  test('unknown route gets checked by default', () => expect(run(), isTrue));
  test(
    'healthy fresh route skips delay',
    () => expect(run(uncertain: false), isFalse),
  );
  test(
    'degraded route gets checked',
    () => expect(run(uncertain: true), isTrue),
  );
  test('manual every-play remains unconditional for eligible routes', () {
    expect(run(manual: true, adaptive: false, uncertain: false), isTrue);
  });
  test('adaptive can be disabled independently', () {
    expect(run(adaptive: false), isFalse);
  });
  test('single route DUMB never gets Emby probe even manual', () {
    expect(run(routes: 1, emby: false, manual: true), isFalse);
    expect(run(routes: 1, manual: true), isFalse);
    expect(run(emby: false, manual: true), isFalse);
  });
  test('manual bitrate always preserved after testing routes', () {
    expect(SipflixPreflightController.preserveManualCap('20', 5), 20);
    expect(SipflixPreflightController.preserveManualCap('20', null), 20);
    expect(SipflixPreflightController.preserveManualCap('auto', 5), 5);
    expect(SipflixPreflightController.preserveManualCap('auto', null), isNull);
  });
  test('health includes route, expiry and required source bitrate', () {
    var now = DateTime.utc(2026, 10, 23);
    final selector = SipflixRouteSelector(
      currentSession: () => null,
      playbackBusy: () => false,
      probe: (_, _, _) async => null,
      apply: (_, _, _) async => false,
      now: () => now,
    );
    expect(selector.needsPreflight('server', 'https://a', 10), isTrue);
    selector.noteMeasurement('server', 'https://a', 20);
    expect(selector.needsPreflight('server', 'https://a', 10), isFalse);
    expect(selector.needsPreflight('server', 'https://a', 25), isTrue);
    expect(selector.needsPreflight('server', 'https://b', 10), isTrue);
    now = now.add(const Duration(hours: 4));
    expect(selector.needsPreflight('server', 'https://a', 10), isTrue);
  });
}
