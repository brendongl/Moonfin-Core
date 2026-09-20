import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/android_codec_capability_probe.dart';
import 'package:moonfin/playback/device_profile_builder.dart';
import 'package:moonfin/util/platform_detection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.moonfin.androidtv/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    PlatformDetection.setTvMode(true);
    PlatformDetection.setMediaCodecCapabilities(null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    PlatformDetection.setMediaCodecCapabilities(null);
    PlatformDetection.setTvMode(false);
  });

  void expectPlayableH264() {
    final profile = DeviceProfileBuilder.build(
      supportsAvc: PlatformDetection.supportsAvc,
      avcMainLevel: PlatformDetection.avcMainLevel,
    );
    final profiles = (profile['CodecProfiles'] as List).where(
      (p) => p['Codec'] == 'h264',
    );
    expect(
      profiles.any(
        (p) => (p['Conditions'] as List).any(
          (c) =>
              c['Property'] == 'VideoProfile' &&
              c['Condition'] == 'Equals' &&
              c['Value'] == 'none',
        ),
      ),
      isFalse,
    );
    expect(
      profiles.any(
        (p) => (p['ApplyConditions'] as List? ?? []).any(
          (c) => c['Property'] == 'VideoProfile' && c['Value'] == 'main',
        ),
      ),
      isTrue,
    );
  }

  for (final failure in ['missing', 'throws', 'null', 'empty']) {
    testWidgets(
      '$failure codec probe retains playable H264 after retries',
      (tester) async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (failure == 'missing') throw MissingPluginException();
          if (failure == 'throws') {
            throw PlatformException(code: 'probe_failed');
          }
          return failure == 'empty' ? <String, dynamic>{} : null;
        });
        await detectAndSetAndroidCodecCapabilities();
        expectPlayableH264();
        for (final seconds in [2, 4, 8, 16]) {
          await tester.pump(Duration(seconds: seconds));
        }
        expectPlayableH264();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'a stalled probe times out and a later probe restores full capabilities',
    (tester) async {
      var calls = 0;
      final stalled = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (++calls == 1) return stalled.future;
        return {'supportsAvc': true, 'avcMainLevel': 52, 'supportsHevc': true};
      });
      final detection = detectAndSetAndroidCodecCapabilities();
      expectPlayableH264();
      await tester.pump(const Duration(seconds: 3));
      await detection;
      await tester.pump(const Duration(seconds: 2));
      expect(PlatformDetection.avcMainLevel, 52);
      expect(PlatformDetection.supportsHevc, isTrue);
      stalled.complete({});
      await tester.pump();
      expect(PlatformDetection.avcMainLevel, 52);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets('null full probe retries even after the AVC floor was seeded', (tester) async {
    var probes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'mediaCodecCapabilities') return null;
      if (++probes == 1) return null;
      return {'supportsAvc': true, 'avcMainLevel': 52, 'supportsHevc': true};
    });
    await detectAndSetAndroidCodecCapabilities();
    expectPlayableH264();
    await tester.pump(const Duration(seconds: 2));
    expect(probes, 2);
    expect(PlatformDetection.supportsHevc, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

}
