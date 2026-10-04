/// Sipflix: after a mid-play network outage recovers, the native player can
/// keep reporting `isBuffering=true` for 30-40s after it is already decoding
/// and advancing again (R3-A gauntlet finding, 2026-10-05) — the raw flag
/// lags real recovery. The "Loading Stream..." overlay must not outlive
/// actual playback progress: clear it as soon as the reported position has
/// visibly moved, instead of waiting for the backend's buffering flag to
/// catch up.
///
/// Pure, timestamp-driven logic kept separate from the widget so it can be
/// unit tested without a Flutter test harness.
class BufferingOverlayTracker {
  BufferingOverlayTracker({
    this.advanceThreshold = const Duration(milliseconds: 200),
    this.graceWindow = const Duration(seconds: 2),
  });

  /// Minimum forward position delta between two reports to count as "the
  /// player visibly advanced", not just clock jitter/rounding.
  final Duration advanceThreshold;

  /// How long a detected advance keeps suppressing the overlay. Short enough
  /// that a genuine new stall (position frozen again) re-shows it quickly,
  /// long enough to ride out the 250ms native state-ticker's sampling gaps.
  final Duration graceWindow;

  Duration? _lastPosition;
  DateTime? _advancedAt;

  /// Feed the latest reported position + the time it was observed. Returns
  /// whether the player should be considered "recently advanced" as of now
  /// — i.e. the buffering overlay should stay hidden even if the raw
  /// buffering flag is still true.
  bool onPosition(Duration position, DateTime now) {
    final last = _lastPosition;
    _lastPosition = position;
    if (last != null && position - last >= advanceThreshold) {
      _advancedAt = now;
    }
    final advancedAt = _advancedAt;
    if (advancedAt == null) return false;
    return now.difference(advancedAt) < graceWindow;
  }

  /// Whether the buffering overlay should be shown, combining the raw
  /// backend flag with the position-advance override above.
  bool shouldShowOverlay({
    required bool rawBuffering,
    required Duration position,
    required DateTime now,
  }) {
    if (!rawBuffering) return false;
    final advancedRecently = onPosition(position, now);
    return !advancedRecently;
  }

  void reset() {
    _lastPosition = null;
    _advancedAt = null;
  }
}
