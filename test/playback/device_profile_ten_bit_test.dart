import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/device_profile_builder.dart';

/// A codec profile's conditions for [codec], as {Property: Condition} plus the
/// values, so a test can ask what shape a constraint was expressed in.
List<Map<String, dynamic>> _conditionsFor(
  Map<String, dynamic> profile,
  String codec,
) {
  final out = <Map<String, dynamic>>[];
  for (final raw in profile['CodecProfiles'] as List<dynamic>? ?? const []) {
    final cp = raw as Map<dynamic, dynamic>;
    if (cp['Type'] != 'Video' || cp['Codec'] != codec) continue;
    for (final rawCond in cp['Conditions'] as List<dynamic>? ?? const []) {
      out.add((rawCond as Map).cast<String, dynamic>());
    }
  }
  return out;
}

bool _hasBitDepthCeiling(Map<String, dynamic> profile, String codec) =>
    _conditionsFor(profile, codec).any((c) =>
        c['Property'] == 'VideoBitDepth' &&
        c['Condition'] == 'LessThanEqual' &&
        c['Value'] == '8');

// Emby serialises only POSITIVE codec conditions into the transcode URL. A
// bare `NotEquals VideoProfile 'high 10'` therefore blocks direct play and then
// vanishes: the server picks "directstream" and copies the 10-bit bitstream to
// a decoder that cannot read it, which is why 10-bit anime rips came out blocky
// on the Allwinner boxes. Verified against Emby 4.9.5 PlaybackInfo on
// 2026-08-20: NotEquals emitted no parameter, `VideoBitDepth LessThanEqual 8`
// emitted `h264-videobitdepth=8`, and 8-bit files direct-played under both.
// Sipflix fork: since 2.7.0 upstream vetoes 10-bit h264/hevc with a positive
// VideoProfile allow-list (which does reach the URL), so only AV1 still needs
// the bit-depth ceiling here.
void main() {
  group('10-bit veto reaches the server', () {
    test('av1 without Main 10 support carries a bit-depth ceiling', () {
      final profile = DeviceProfileBuilder.build(
        supportsAv1: true,
        supportsAv1Main10: false,
      );
      expect(_hasBitDepthCeiling(profile, 'av1'), isTrue);
    });

  });

  group('hardware that CAN decode 10-bit is not capped', () {
    test('h264 with High 10 support has no bit-depth ceiling', () {
      final profile = DeviceProfileBuilder.build(
        supportsAvc: true,
        supportsAvcHigh10: true,
        avcMainLevel: 51,
        avcHigh10Level: 51,
      );
      expect(_hasBitDepthCeiling(profile, 'h264'), isFalse);
    });

    test('hevc with Main 10 support has no bit-depth ceiling', () {
      final profile = DeviceProfileBuilder.build(
        supportsHevc: true,
        supportsHevcMain10: true,
        hevcMainLevel: 120,
      );
      expect(_hasBitDepthCeiling(profile, 'hevc'), isFalse);
    });

    test('av1 with Main 10 support has no bit-depth ceiling', () {
      final profile = DeviceProfileBuilder.build(
        supportsAv1: true,
        supportsAv1Main10: true,
      );
      expect(_hasBitDepthCeiling(profile, 'av1'), isFalse);
    });
  });
}
