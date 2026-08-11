import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Sipflix "Auto" quality resolves a cap from two independent signals: a speed
// measurement taken while nothing is playing, and a ceiling learned when real
// playback stalls. The measurement can be hours old — which is exactly the case
// Auto used to get wrong, because a box measured off-peak kept an optimistic cap
// into the evening congestion — so the learned ceiling has to be able to win.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<UserPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final store = PreferenceStore();
    await store.init();
    return UserPreferences(store);
  }

  final now = DateTime(2026, 8, 10, 21, 0);
  int msAgo(Duration d) => now.subtract(d).millisecondsSinceEpoch;

  group('Auto cap from a measurement', () {
    test('no measurement means no cap, so Auto never guesses low', () async {
      final prefs = await prefsWith({});
      expect(prefs.autoBitrateCapMbps(now: now), isNull);
    });

    test('a fresh measurement caps at 80% of it', () async {
      final prefs = await prefsWith({
        'flutter.sipflix_measured_bandwidth_mbps': 50.0,
        'flutter.sipflix_measured_bandwidth_at': msAgo(const Duration(minutes: 5)),
      });
      expect(prefs.autoBitrateCapMbps(now: now), 40);
    });

    test('a fast link gets no cap at all, so it direct plays', () async {
      final prefs = await prefsWith({
        'flutter.sipflix_measured_bandwidth_mbps': 400.0,
        'flutter.sipflix_measured_bandwidth_at': msAgo(const Duration(minutes: 5)),
      });
      expect(prefs.autoBitrateCapMbps(now: now), isNull);
    });

    test('a stale measurement is discarded rather than trusted', () async {
      final prefs = await prefsWith({
        'flutter.sipflix_measured_bandwidth_mbps': 50.0,
        'flutter.sipflix_measured_bandwidth_at': msAgo(const Duration(hours: 5)),
      });
      expect(prefs.autoBitrateCapMbps(now: now), isNull);
    });
  });

  group('Ceiling learned from real buffering', () {
    test('beats a stale-but-optimistic measurement', () async {
      // The 21:00 case: measured 50 Mbps this afternoon, but playback is
      // stalling now and settled at 8 Mbps.
      final prefs = await prefsWith({
        'flutter.sipflix_measured_bandwidth_mbps': 50.0,
        'flutter.sipflix_measured_bandwidth_at': msAgo(const Duration(hours: 3)),
        'flutter.sipflix_auto_ceiling_mbps': 8,
        'flutter.sipflix_auto_ceiling_at': msAgo(const Duration(minutes: 2)),
      });
      expect(prefs.autoBitrateCapMbps(now: now), 8);
    });

    test('does not raise a cap the measurement already put lower', () async {
      final prefs = await prefsWith({
        'flutter.sipflix_measured_bandwidth_mbps': 10.0, // -> 8 Mbps
        'flutter.sipflix_measured_bandwidth_at': msAgo(const Duration(minutes: 5)),
        'flutter.sipflix_auto_ceiling_mbps': 30,
        'flutter.sipflix_auto_ceiling_at': msAgo(const Duration(minutes: 2)),
      });
      expect(prefs.autoBitrateCapMbps(now: now), 8);
    });

    test('applies even with no measurement at all', () async {
      final prefs = await prefsWith({
        'flutter.sipflix_auto_ceiling_mbps': 5,
        'flutter.sipflix_auto_ceiling_at': msAgo(const Duration(minutes: 2)),
      });
      expect(prefs.autoBitrateCapMbps(now: now), 5);
    });

    test('expires, so one bad evening does not pin the box low forever', () async {
      final prefs = await prefsWith({
        'flutter.sipflix_auto_ceiling_mbps': 5,
        'flutter.sipflix_auto_ceiling_at': msAgo(const Duration(hours: 7)),
      });
      expect(prefs.autoCeilingMbps(now: now), isNull);
      expect(prefs.autoBitrateCapMbps(now: now), isNull);
    });

    test('note and clear round-trip', () async {
      final prefs = await prefsWith({});
      await prefs.noteAutoCeiling(12);
      expect(prefs.autoCeilingMbps(), 12);
      await prefs.clearAutoCeiling();
      expect(prefs.autoCeilingMbps(), isNull);
    });
  });

  group('An explicit user cap always wins', () {
    test('the chosen number is used, not the measurement', () async {
      final prefs = await prefsWith({
        'flutter.pref_max_bitrate': '20',
        'flutter.sipflix_measured_bandwidth_mbps': 50.0,
        'flutter.sipflix_measured_bandwidth_at': msAgo(const Duration(minutes: 5)),
      });
      expect(prefs.resolveMaxBitrateMbps(now: now), 20);
    });

    test('Auto falls through to the measured cap', () async {
      final prefs = await prefsWith({
        'flutter.pref_max_bitrate': 'auto',
        'flutter.sipflix_measured_bandwidth_mbps': 50.0,
        'flutter.sipflix_measured_bandwidth_at': msAgo(const Duration(minutes: 5)),
      });
      expect(prefs.resolveMaxBitrateMbps(now: now), 40);
    });
  });
}
