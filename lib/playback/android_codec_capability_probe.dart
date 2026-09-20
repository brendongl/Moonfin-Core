import 'dart:async';

import 'package:flutter/services.dart';

import '../util/platform_detection.dart';

/// A cold-start probe can race codec enumeration and return a map with no
/// usable H264 support. Every Android device that reaches this code plays
/// H264, so such a result is a transient failure, not a real capability.
bool _codecCapsLookDegenerate(Map<String, dynamic> caps) {
  final supportsAvc = caps['supportsAvc'] == true;
  final avcMainLevel = caps['avcMainLevel'];
  return !supportsAvc || avcMainLevel is! int || avcMainLevel <= 0;
}

Future<Map<String, dynamic>?> _queryCodecCaps(MethodChannel channel) async {
  final raw = await channel
      .invokeMethod<Map<dynamic, dynamic>>(
        'mediaCodecCapabilities',
        <String, dynamic>{'includeSoftwareDecoders': !PlatformDetection.isTV},
      )
      .timeout(const Duration(seconds: 3));
  return raw?.map((key, value) => MapEntry(key.toString(), value));
}

/// AVC Level 4.1 (1080p) — the decode floor every Android device running this
/// app clears.
const int _avcFloorLevel = 41;

/// Repairs a degenerate probe result so the device profile still advertises
/// H264. Without this the profile carries no h264 codec profiles at all, the
/// server receives `h264-profile=none`, and every encoder it owns — hardware
/// *and* software — fails the client-profile match, so each transcode segment
/// returns HTTP 500 and playback dies. A needless transcode is recoverable;
/// an unplayable stream is not.
///
/// Only the AVC fields are filled in, and only up to Level 4.1 (1080p). That
/// is the floor every Android device running this app clears, so the guess
/// cannot promise decoding the device does not have. Everything else the probe
/// reported is left untouched.
Map<String, dynamic> _withAvcFloor(Map<String, dynamic> caps) {
  return <String, dynamic>{
    ...caps,
    'supportsAvc': true,
    'avcMainLevel':
        caps['avcMainLevel'] is int && (caps['avcMainLevel'] as int) > 0
        ? caps['avcMainLevel']
        : _avcFloorLevel,
  };
}

/// Re-probes in the background when the startup result looked degenerate.
/// The native query enumerates codecs on the platform main thread, so the
/// retries must never extend the launch path. The device profile is built
/// per playback, so a corrected result applied here still fixes the next
/// playback without a restart.
///
/// Backs off between attempts: enumeration loses the race when the device is
/// busiest right after boot, and two tries two seconds apart is not enough
/// headroom on slow hardware. Whatever the outcome the AVC floor from
/// [_withAvcFloor] stays in place, so giving up degrades to extra transcodes
/// rather than to failed playback.
Future<void> _retryCodecCapsOffLaunchPath(MethodChannel channel) async {
  var delay = const Duration(seconds: 2);
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(delay);
    delay *= 2;
    try {
      final caps = await _queryCodecCaps(channel);
      if (caps != null && !_codecCapsLookDegenerate(caps)) {
        PlatformDetection.setMediaCodecCapabilities(caps);
        return;
      }
    } catch (_) {
      // A failed probe says nothing about the next one; keep trying.
    }
  }
}

Future<void> detectAndSetAndroidCodecCapabilities() async {
  if (!PlatformDetection.isAndroid) return;
  const channel = MethodChannel('org.moonfin.androidtv/platform');
  // Seed before invoking native code: missing channels and thrown probes must
  // never leave H264 disabled for the entire session.
  PlatformDetection.setMediaCodecCapabilities(
    _withAvcFloor(PlatformDetection.mediaCodecCapabilities),
  );
  try {
    final codecCaps = await _queryCodecCaps(channel);
    if (codecCaps != null) {
      // A degenerate cold-start result would otherwise poison the device
      // profile until app restart: no h264 profiles reach the server, so it
      // can pick no encoder and every transcode segment 500s. Apply the floor
      // now and keep re-probing for the device's real capabilities.
      final degenerate = _codecCapsLookDegenerate(codecCaps);
      PlatformDetection.setMediaCodecCapabilities(
        degenerate ? _withAvcFloor(codecCaps) : codecCaps,
      );
      if (degenerate) {
        unawaited(_retryCodecCapsOffLaunchPath(channel));
      }
      return;
    }

    final legacyDvCaps = await channel
        .invokeMethod<Map<dynamic, dynamic>>('dolbyVisionCodecCapabilities')
        .timeout(const Duration(seconds: 3));
    PlatformDetection.setDolbyVisionCodecCapabilities(
      legacyDvCaps?.map(
        (key, value) => MapEntry(key.toString(), value == true),
      ),
    );
    // The legacy setter replaces the shared map with Dolby Vision fields.
    // Restore AVC before returning, then retry the complete native probe.
    PlatformDetection.setMediaCodecCapabilities(
      _withAvcFloor(PlatformDetection.mediaCodecCapabilities),
    );
    unawaited(_retryCodecCapsOffLaunchPath(channel));
  } catch (_) {
    unawaited(_retryCodecCapsOffLaunchPath(channel));
  }
}
