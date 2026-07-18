/// Sipflix: detects sustained playback buffering and suggests a lower bitrate.
///
/// Ported from the old Kotlin fork's PlaybackController logic, hardened against
/// false positives:
/// - Events are ignored until playback has actually started
///   ([markPlaybackStarted]) plus [postStartGrace], so the initial buffer fill
///   and the TCP slow-start / cold-CDN ramp never trigger the prompt.
/// - Callers should only record stalls lasting >= [minStallDuration] (the
///   player screen arms a timer per stall), so brief post-seek rebuffers on a
///   healthy link don't count.
/// - If [threshold] qualifying stalls occur within [window], offer the
///   adaptation dialog ONCE per item; [reset] re-arms (new item, or after a
///   lower bitrate was applied so a still-starving link can step down again).
class SipflixBitrateWatchdog {
  static const int threshold = 3;
  static const Duration window = Duration(seconds: 60);

  /// Grace after playback start: cold TCP connections ramp via slow-start and
  /// CDN edges may be cache-cold, so the first seconds under-deliver even on a
  /// healthy link (same effect the speedtest's warm-then-measure corrects for).
  static const Duration postStartGrace = Duration(seconds: 15);

  /// Only stalls at least this long qualify (filters seek rebuffers).
  static const Duration minStallDuration = Duration(seconds: 3);

  /// Common bitrate tiers in Mbps (descending), matching the old fork.
  static const List<int> tiers = [120, 80, 60, 40, 30, 20, 15, 10, 8, 5, 3];

  final List<DateTime> _events = [];
  bool _offered = false;
  DateTime? _playbackStartedAt;

  /// Mark that playback actually started rendering. Idempotent; cleared by
  /// [reset] so each (re)start gets a fresh grace window.
  void markPlaybackStarted([DateTime? now]) {
    _playbackStartedAt ??= now ?? DateTime.now();
  }

  /// Record a sustained buffering event. Returns true exactly once when the
  /// number of qualifying events within [window] first reaches [threshold].
  /// Events before playback start + [postStartGrace] are ignored. [now] is
  /// injectable for testing; defaults to the current time.
  bool recordAndShouldOffer([DateTime? now]) {
    if (_offered) return false;
    now ??= DateTime.now();
    final started = _playbackStartedAt;
    if (started == null || now.difference(started) < postStartGrace) {
      return false;
    }
    _events.add(now);
    _events.removeWhere((t) => now!.difference(t) > window);
    if (_events.length >= threshold) {
      _offered = true;
      return true;
    }
    return false;
  }

  /// Reset tracking: new item, or a bitrate change was just applied (the
  /// stream restarts, so it gets a fresh start grace and may offer again).
  void reset() {
    _events.clear();
    _offered = false;
    _playbackStartedAt = null;
  }

  /// Suggest the next tier strictly below [currentMbps] (minimum 3 Mbps).
  static int suggestLowerBitrate(int currentMbps) {
    for (final tier in tiers) {
      if (tier < currentMbps) return tier;
    }
    return 3;
  }
}
