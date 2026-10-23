import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/media3_player_backend.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _control = MethodChannel('moonfin/media3_video_control');
const _events = MethodChannel('moonfin/media3_video_events');

Future<void> _send(Map<String, dynamic> payload) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(payload),
        (_) {},
      );
}

// Issue #1189: the live edge Media3 reports becomes the window the live
// player rewinds through, on the same clock as the position.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Media3PlayerBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, (_) async => null);
    backend = Media3PlayerBackend(UserPreferences(store));
  });

  tearDown(() {
    backend.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, null);
  });

  Future<void> state({int? liveEdgeMs}) async {
    await _send(<String, dynamic>{
      'event': 'state',
      'positionMs': 7_000_000,
      'durationMs': 7_200_000,
      'liveEdgeMs': ?liveEdgeMs,
    });
    await pumpEventQueue();
  }

  test('a reported live edge is the window from the start to it', () async {
    await state(liveEdgeMs: 7_194_000);

    final window = backend.liveSeekWindow!;
    expect(window.start, Duration.zero);
    expect(window.edge, const Duration(milliseconds: 7_194_000));
  });

  test('a stream without one has nothing to rewind through', () async {
    await state(liveEdgeMs: 7_194_000);
    await state();

    expect(backend.liveSeekWindow, isNull);
  });
}
