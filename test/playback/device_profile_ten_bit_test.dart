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
void main() {
  group('10-bit veto reaches the server', () {
    test('h264 without High 10 support carries a bit-depth ceiling', () {
      final profile = DeviceProfileBuilder.build(
        supportsAvc: true,
        supportsAvcHigh10: false,
        avcMainLevel: 51,
      );
      expect(_hasBitDepthCeiling(profile, 'h264'), isTrue);
    });

    test('hevc without Main 10 support carries a bit-depth ceiling', () {
      final profile = DeviceProfileBuilder.build(
        supportsHevc: true,
        supportsHevcMain10: false,
        hevcMainLevel: 120,
      );
      expect(_hasBitDepthCeiling(profile, 'hevc'), isTrue);
    });

    test('av1 without Main 10 support carries a bit-depth ceiling', () {
      final profile = DeviceProfileBuilder.build(
        supportsAv1: true,
        supportsAv1Main10: false,
      );
      expect(_hasBitDepthCeiling(profile, 'av1'), isTrue);
    });

    test('the old NotEquals veto is kept alongside it', () {
      final profile = DeviceProfileBuilder.build(
        supportsAvc: true,
        supportsAvcHigh10: false,
        avcMainLevel: 51,
      );
      expect(
        _conditionsFor(profile, 'h264').any((c) =>
            c['Property'] == 'VideoProfile' &&
            c['Condition'] == 'NotEquals' &&
            c['Value'] == 'high 10'),
        isTrue,
        reason: 'still needed for a file whose BitDepth metadata is missing',
      );
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
