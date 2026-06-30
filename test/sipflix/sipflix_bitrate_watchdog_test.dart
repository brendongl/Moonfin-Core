import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_bitrate_watchdog.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 0, 0, 0);

  group('SipflixBitrateWatchdog.recordAndShouldOffer', () {
    test('offers exactly once after threshold events within the window', () {
      final w = SipflixBitrateWatchdog();
      expect(w.recordAndShouldOffer(t0), isFalse); // 1
      expect(w.recordAndShouldOffer(t0.add(const Duration(seconds: 5))), isFalse); // 2
      expect(w.recordAndShouldOffer(t0.add(const Duration(seconds: 10))), isTrue); // 3 -> offer
      // Already offered: never offers again until reset.
      expect(w.recordAndShouldOffer(t0.add(const Duration(seconds: 11))), isFalse);
      expect(w.recordAndShouldOffer(t0.add(const Duration(seconds: 12))), isFalse);
    });

    test('does not offer when events are spread beyond the window', () {
      final w = SipflixBitrateWatchdog();
      expect(w.recordAndShouldOffer(t0), isFalse);
      expect(w.recordAndShouldOffer(t0.add(const Duration(seconds: 40))), isFalse);
      // 70s after the first: the first event is pruned, so only 2 remain in window.
      expect(w.recordAndShouldOffer(t0.add(const Duration(seconds: 70))), isFalse);
      // One more within the window of the last two -> reaches 3 -> offer.
      expect(w.recordAndShouldOffer(t0.add(const Duration(seconds: 80))), isTrue);
    });

    test('reset re-arms the watchdog', () {
      final w = SipflixBitrateWatchdog();
      w.recordAndShouldOffer(t0);
      w.recordAndShouldOffer(t0);
      expect(w.recordAndShouldOffer(t0), isTrue);
      w.reset();
      expect(w.recordAndShouldOffer(t0), isFalse);
      expect(w.recordAndShouldOffer(t0), isFalse);
      expect(w.recordAndShouldOffer(t0), isTrue);
    });
  });

  group('SipflixBitrateWatchdog.suggestLowerBitrate', () {
    test('returns the next tier strictly below current', () {
      expect(SipflixBitrateWatchdog.suggestLowerBitrate(200), 120);
      expect(SipflixBitrateWatchdog.suggestLowerBitrate(120), 80);
      expect(SipflixBitrateWatchdog.suggestLowerBitrate(100), 80);
      expect(SipflixBitrateWatchdog.suggestLowerBitrate(40), 30);
      expect(SipflixBitrateWatchdog.suggestLowerBitrate(5), 3);
    });

    test('never goes below 3 Mbps', () {
      expect(SipflixBitrateWatchdog.suggestLowerBitrate(3), 3);
      expect(SipflixBitrateWatchdog.suggestLowerBitrate(1), 3);
    });
  });
}
