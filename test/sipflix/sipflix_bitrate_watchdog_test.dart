import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_bitrate_watchdog.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 0, 0, 0);

  group('SipflixBitrateWatchdog.recordAndShouldOffer', () {
    // Events only count once playback has started and the post-start grace has
    // elapsed, so every case arms the watchdog at t0 and records from t0 + 20s.
    SipflixBitrateWatchdog armed() =>
        SipflixBitrateWatchdog()..markPlaybackStarted(t0);
    final start = t0.add(const Duration(seconds: 20));

    test('offers exactly once after threshold events within the window', () {
      final w = armed();
      expect(w.recordAndShouldOffer(start), isFalse); // 1
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 5))), isFalse); // 2
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 10))), isTrue); // 3 -> offer
      // Already offered: never offers again until reset.
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 11))), isFalse);
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 12))), isFalse);
    });

    test('does not offer when events are spread beyond the window', () {
      final w = armed();
      expect(w.recordAndShouldOffer(start), isFalse);
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 40))), isFalse);
      // 70s after the first: the first event is pruned, so only 2 remain in window.
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 70))), isFalse);
      // One more within the window of the last two -> reaches 3 -> offer.
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 80))), isTrue);
    });

    test('reset re-arms the watchdog', () {
      final w = armed();
      w.recordAndShouldOffer(start);
      w.recordAndShouldOffer(start);
      expect(w.recordAndShouldOffer(start), isTrue);
      w.reset();
      // reset() clears the start marker too, so the watchdog must be re-armed.
      w.markPlaybackStarted(start);
      final restart = start.add(const Duration(seconds: 20));
      expect(w.recordAndShouldOffer(restart), isFalse);
      expect(w.recordAndShouldOffer(restart), isFalse);
      expect(w.recordAndShouldOffer(restart), isTrue);
    });

    test('a stall inside the post-start grace is ignored', () {
      final w = armed();
      for (var i = 0; i < 5; i++) {
        expect(
          w.recordAndShouldOffer(t0.add(Duration(seconds: i))),
          isFalse,
          reason: 'start-up rebuffering must not count as a link problem',
        );
      }
    });

    test('the refill after a user seek does not count as a stall', () {
      final w = armed();
      expect(w.recordAndShouldOffer(start), isFalse);
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 5))), isFalse);
      w.markSeek(start.add(const Duration(seconds: 6)));
      // Would have been the third qualifying event, but it is the seek's own refill.
      expect(w.recordAndShouldOffer(start.add(const Duration(seconds: 8))), isFalse);
      // markSeek re-arms the start grace, so recording resumes well after it.
      final after = start.add(const Duration(seconds: 45));
      expect(w.recordAndShouldOffer(after), isTrue);
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
