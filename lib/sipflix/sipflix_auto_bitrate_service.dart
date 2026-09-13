import 'dart:async';

import 'package:logger/logger.dart';

import '../data/services/media_server_client_factory.dart';
import '../preference/user_preferences.dart';
import 'sipflix_bandwidth_probe.dart';
import 'sipflix_log.dart';

/// Sipflix: keeps the measured link speed behind the "Auto" quality setting
/// fresh, so Auto caps at what the connection can actually carry instead of
/// either guessing or never capping at all.
///
/// Deliberately conservative about *when* it runs:
///  * only while the quality setting is 'auto' (an explicit user cap wins),
///  * never while something is playing — a probe must not steal bandwidth from
///    the stream it is meant to protect,
///  * only when the stored measurement is missing or older than the TTL,
///  * at most one probe in flight, and failures are silent (Auto simply keeps
///    its previous behaviour).
class SipflixAutoBitrateService {
  SipflixAutoBitrateService({
    required UserPreferences prefs,
    required MediaServerClientFactory clientFactory,
    SipflixBandwidthProbe? probe,
    Logger? logger,
  })  : _prefs = prefs,
        _clientFactory = clientFactory,
        _probe = probe ?? SipflixBandwidthProbe(),
        _logger = logger ?? sipflixLogger();

  final UserPreferences _prefs;
  final MediaServerClientFactory _clientFactory;
  final SipflixBandwidthProbe _probe;
  final Logger _logger;

  bool _inFlight = false;

  /// True when a fresh measurement is needed for Auto to be meaningful.
  bool get needsMeasurement {
    if (int.tryParse(_prefs.get(UserPreferences.maxBitrate)) != null) {
      return false; // explicit cap chosen; measuring would be pointless
    }
    final at = _prefs.get(UserPreferences.measuredBandwidthAt);
    if (at <= 0 || _prefs.get(UserPreferences.measuredBandwidthMbps) <= 0) {
      return true;
    }
    final age =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age.isNegative || age > UserPreferences.measuredBandwidthTtl;
  }

  /// Measures and stores the link speed if one is needed. [isPlaybackActive]
  /// lets the caller veto the probe while a stream is running.
  ///
  /// Returns the Mbps stored, or null when nothing was measured.
  Future<double?> refreshIfStale({
    bool force = false,
    bool isPlaybackActive = false,
  }) async {
    if (_inFlight || isPlaybackActive) return null;
    if (!force && !needsMeasurement) return null;
    _inFlight = true;
    try {
      final client = _clientFactory.getActiveClient();
      final mbps = await _probe.measureMbps(
        baseUrl: client.baseUrl,
        accessToken: client.accessToken,
      );
      if (mbps == null || mbps <= 0) return null;
      await _prefs.set(UserPreferences.measuredBandwidthMbps, mbps);
      await _prefs.set(
        UserPreferences.measuredBandwidthAt,
        DateTime.now().millisecondsSinceEpoch,
      );
      _logger.i('Sipflix auto bitrate: measured ${mbps.toStringAsFixed(1)} Mbps '
          '-> cap ${_prefs.autoBitrateCapMbps() ?? "unlimited"} Mbps');
      return mbps;
    } catch (e) {
      _logger.d('Sipflix auto bitrate refresh skipped: $e');
      return null;
    } finally {
      _inFlight = false;
    }
  }
}
