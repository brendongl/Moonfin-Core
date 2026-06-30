/// Sipflix: detects repeated playback buffering and suggests a lower bitrate.
///
/// Ported from the old Kotlin fork's PlaybackController logic: if [threshold]
/// buffering events occur within [window], offer the adaptation dialog ONCE per
/// item. Reset on each new item via [reset].
class SipflixBitrateWatchdog {
  static const int threshold = 3;
  static const Duration window = Duration(seconds: 60);

  /// Common bitrate tiers in Mbps (descending), matching the old fork.
  static const List<int> tiers = [120, 80, 60, 40, 30, 20, 15, 10, 8, 5, 3];

  final List<DateTime> _events = [];
  bool _offered = false;

  /// Record a buffering event. Returns true exactly once when the number of
  /// buffering events within [window] first reaches [threshold]. [now] is
  /// injectable for testing; defaults to the current time.
  bool recordAndShouldOffer([DateTime? now]) {
    if (_offered) return false;
    now ??= DateTime.now();
    _events.add(now);
    _events.removeWhere((t) => now!.difference(t) > window);
    if (_events.length >= threshold) {
      _offered = true;
      return true;
    }
    return false;
  }

  /// Reset tracking for a new item.
  void reset() {
    _events.clear();
    _offered = false;
  }

  /// Suggest the next tier strictly below [currentMbps] (minimum 3 Mbps).
  static int suggestLowerBitrate(int currentMbps) {
    for (final tier in tiers) {
      if (tier < currentMbps) return tier;
    }
    return 3;
  }
}
