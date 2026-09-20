import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/media3_player_backend.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const control = MethodChannel('moonfin/media3_video_control');
  const events = MethodChannel('moonfin/media3_video_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> send(Map<String, Object> value) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  Future<Media3PlayerBackend> backend(List<String> calls) async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    return Media3PlayerBackend(UserPreferences(store));
  }

  testWidgets('metadata and trickling buffer cannot hide an endless startup', (
    tester,
  ) async {
    final calls = <String>[];
    final player = await backend(calls);
    final errors = <Map<String, dynamic>>[];
    player.errorStream.listen(errors.add);
    await player.play('https://example.invalid/video');
    await send({
      'event': 'state',
      'durationMs': 3300000,
      'bufferedMs': 917,
      'positionMs': 0,
      'isPlaying': false,
      'isBuffering': true,
    });
    await tester.pump(const Duration(seconds: 59));
    expect(errors, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(errors.single['kind'], 'startupTimeout');
    expect(calls.last, 'pause');
    await tester.pump(const Duration(minutes: 2));
    expect(errors, hasLength(1));
    player.dispose();
    await tester.pump();
  });

  for (final action in ['playing', 'firstFrame', 'pause', 'stop', 'preview']) {
    testWidgets('$action cancels startup failure', (tester) async {
      final player = await backend([]);
      final errors = <Map<String, dynamic>>[];
      player.errorStream.listen(errors.add);
      await player.play({
        'url': 'https://example.invalid/video',
        'preview': action == 'preview',
      });
      if (action == 'playing') {
        await send({'event': 'state', 'isPlaying': true, 'isBuffering': false});
      } else if (action == 'firstFrame') {
        await send({'event': 'firstFrameRendered'});
      } else if (action == 'pause') {
        await player.pause();
      } else if (action == 'stop') {
        await player.stop();
      }
      await tester.pump(const Duration(seconds: 65));
      expect(errors, isEmpty);
      player.dispose();
      await tester.pump();
    });
  }

  testWidgets('a new stream gets its own full startup deadline', (
    tester,
  ) async {
    final player = await backend([]);
    final errors = <Map<String, dynamic>>[];
    player.errorStream.listen(errors.add);
    await player.play('https://example.invalid/old');
    await tester.pump(const Duration(seconds: 40));
    await player.play('https://example.invalid/new');
    await tester.pump(const Duration(seconds: 40));
    expect(errors, isEmpty);
    await tester.pump(const Duration(seconds: 21));
    expect(errors, hasLength(1));
    player.dispose();
    await tester.pump();
  });
}
