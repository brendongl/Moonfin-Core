import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/playback/buffering_overlay_tracker.dart';

void main() {
  group('BufferingOverlayTracker', () {
    test('shows overlay on a genuine stall (position frozen)', () {
      final tracker = BufferingOverlayTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // First sample has no prior position to compare against, so there is
      // no evidence of an advance yet -> show.
      expect(
        tracker.shouldShowOverlay(
          rawBuffering: true,
          position: const Duration(seconds: 10),
          now: t0,
        ),
        isTrue,
      );
      // Position stays frozen across subsequent ticks -> real stall -> show.
      for (var i = 1; i <= 8; i++) {
        final shown = tracker.shouldShowOverlay(
          rawBuffering: true,
          position: const Duration(seconds: 10),
          now: t0.add(Duration(milliseconds: 250 * i)),
        );
        if (i >= 1) expect(shown, isTrue, reason: 'tick $i');
      }
    });

    test('clears as soon as position visibly advances, even if the raw '
        'buffering flag is still true', () {
      final tracker = BufferingOverlayTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Stalled for a while: overlay shows.
      tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 85),
        now: t0,
      );
      expect(
        tracker.shouldShowOverlay(
          rawBuffering: true,
          position: const Duration(seconds: 85),
          now: t0.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );

      // Position jumps forward (R3-A: native flag lagging real recovery) —
      // the overlay must clear immediately even though rawBuffering is
      // still reported true.
      final now = t0.add(const Duration(seconds: 2));
      final shown = tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 87),
        now: now,
      );
      expect(shown, isFalse);
    });

    test('a suppressed stall re-shows the overlay once the advance grace '
        'window elapses without further progress', () {
      final tracker = BufferingOverlayTracker(
        graceWindow: const Duration(seconds: 2),
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 85),
        now: t0,
      );
      // Advance detected at t0+1s.
      final suppressed = tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 86),
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(suppressed, isFalse);

      // Position stays flat afterwards (stalled again); once the grace
      // window (2s from the advance) elapses, the overlay comes back.
      final reshown = tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 86),
        now: t0.add(const Duration(seconds: 4)),
      );
      expect(reshown, isTrue);
    });

    test('never shows when the raw buffering flag is false', () {
      final tracker = BufferingOverlayTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        tracker.shouldShowOverlay(
          rawBuffering: false,
          position: const Duration(seconds: 10),
          now: t0,
        ),
        isFalse,
      );
    });

    test('reset() clears tracked position/advance state', () {
      final tracker = BufferingOverlayTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 85),
        now: t0,
      );
      tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 87),
        now: t0.add(const Duration(seconds: 1)),
      );
      tracker.reset();
      // After reset, the very next sample is just a new baseline again and
      // must not show as "advanced" by comparing against stale state.
      final shown = tracker.shouldShowOverlay(
        rawBuffering: true,
        position: const Duration(seconds: 200),
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(shown, isTrue);
    });
  });
}
