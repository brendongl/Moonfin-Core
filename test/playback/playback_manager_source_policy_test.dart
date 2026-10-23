import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';
import 'package:moonfin/sipflix/sipflix_4k_policy.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

class _TestBackend extends Fake implements PlayerBackend {
  final _errors = StreamController<Map<String, dynamic>>.broadcast();
  Completer<void>? playGate;
  final List<String> playedUrls = <String>[];
  final List<Duration> startPositions = <Duration>[];
  int stopCalls = 0;
  bool playing = false;
  Duration currentPosition = Duration.zero;

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration =>
      playing ? const Duration(minutes: 30) : Duration.zero;

  @override
  Duration get buffer => Duration.zero;

  @override
  bool get isPlaying => playing;

  @override
  double get playbackSpeed => 1.0;

  @override
  bool get isBuffering => false;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get completedStream => const Stream<bool>.empty();

  @override
  Stream<Map<String, dynamic>>? get errorStream => _errors.stream;

  void emitError(Map<String, dynamic> event) => _errors.add(event);

  @override
  bool get supportsRuntimeTrackSelection => false;

  @override
  bool get canRenderBitmapSubtitles => false;

  @override
  bool get requiresStartupMediaReadyCheck => false;

  @override
  bool get nativelyHandlesStartPosition => true;

  @override
  Map<String, dynamic> getDeviceProfile({
    bool useProgressiveTranscode = false,
  }) => <String, dynamic>{};

  @override
  Future<void> play(
    dynamic mediaItem, {
    Duration startPosition = Duration.zero,
  }) async {
    playedUrls.add((mediaItem as Map<String, dynamic>)['url'] as String);
    startPositions.add(startPosition);
    currentPosition = startPosition;
    playing = true;
    // Holds the first play open so a test can land an error while the manager
    // is still waiting for media. Later plays run straight through.
    final gate = playGate;
    if (gate != null) {
      playGate = null;
      await gate.future;
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }

  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {}

  Future<void> setRepeatMode(RepeatMode mode) async {}

  @override
  void dispose() => _errors.close();
}

class _TestResolver extends MediaStreamResolver {
  int calls = 0;
  final List<String?> requestedMediaSourceIds = <String?>[];
  final List<int?> requestedStartTicks = <int?>[];
  final List<bool> requestedDirectPlay = <bool>[];
  StreamPlayMethod playMethod = StreamPlayMethod.directStream;
  bool isLocalMedia = false;
  List<Map<String, dynamic>> mediaStreams = const [];

  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) async {
    calls++;
    requestedMediaSourceIds.add(mediaSourceId);
    requestedStartTicks.add(startTimeTicks);
    requestedDirectPlay.add(enableDirectPlay);
    final type = mediaItem is Map ? mediaItem['Type'] : mediaItem.type;
    final isLive = type == 'TvChannel' || type == 'LiveTvChannel';
    return StreamResolutionResult(
      streamUrl: 'https://example.test/session-$calls',
      mediaSourceId: mediaSourceId ?? 'source-$calls',
      liveStreamId: isLive ? 'live-$calls' : null,
      playSessionId: 'session-$calls',
      playMethod: playMethod,
      isLocalMedia: isLocalMedia,
      mediaStreams: mediaStreams,
    );
  }
}

class _TestService extends Fake implements PlayerService {
  final transcodingStops = <StreamResolutionResult>[];
  @override
  Future<void> onPlaybackStart(
    dynamic item,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}
  @override
  Future<void> onPlaybackProgress(
    dynamic item,
    StreamResolutionResult resolution,
    Duration position, {
    bool isPaused = false,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? volumeLevel,
    bool? isMuted,
  }) async {}
  @override
  Future<void> onPlaybackStop(
    dynamic item,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
  }) async {}
  @override
  Future<void> closeLiveStream(String id) async {}
  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {
    transcodingStops.add(resolution);
  }

  @override
  void dispose() {}
}

PlaybackManager _manager(
  _TestBackend backend,
  _TestResolver resolver,
  _TestService service,
) => PlaybackManager()
  ..setBackend(backend)
  ..setResolver(resolver)
  ..setPlayerService(service);

class _PolicyItem {
  _PolicyItem(this.id, this.serverId, this.mediaSources);
  final String id;
  final String serverId;
  final List<Map<String, dynamic>> mediaSources;
  String get type => 'Episode';
}

Map<String, dynamic> _source(String id, int width, int size) => {
  'Id': id,
  'Size': size,
  'MediaStreams': [
    {'Type': 'Video', 'Width': width, 'Height': width * 9 ~/ 16},
  ],
};

void main() {
  late _TestBackend backend;
  late _TestResolver resolver;
  late _TestService service;
  late PlaybackManager manager;
  setUp(() {
    backend = _TestBackend();
    resolver = _TestResolver();
    service = _TestService();
    manager = _manager(backend, resolver, service);
    manager.sourceRefusalPolicy = Sipflix4kPolicy.sourceRefusal;
    manager.sourceSelectionPolicy = (item, selected) async => (
      item: item,
      mediaSourceId:
          selected ??
          Sipflix4kPolicy.defaultSource(
            item.mediaSources,
            serverRef: item.serverId,
            cannotPlay4k: false,
          )?['Id']?.toString(),
    );
  });
  tearDown(() => manager.dispose());

  test(
    'Alpha defaults choose smallest for first item and queue next',
    () async {
      final a = _PolicyItem('a', SipflixServers.alphaV2.recordId, [
        _source('a-big', 1920, 900),
        _source('a-small', 1920, 100),
      ]);
      final b = _PolicyItem('b', SipflixServers.alphaV2.recordId, [
        _source('b-big', 1920, 900),
        _source('b-small', 1920, 100),
      ]);
      await manager.playItems([a, b]);
      await manager.next();
      expect(resolver.requestedMediaSourceIds, ['a-small', 'b-small']);
      expect(backend.playedUrls, hasLength(2));
    },
  );

  test('manual allowed Delta version is preserved', () async {
    final item = _PolicyItem('a', SipflixServers.delta.recordId, [
      _source('large', 1920, 900),
      _source('small', 1280, 100),
    ]);
    await manager.playItems([item], mediaSourceId: 'large');
    expect(resolver.requestedMediaSourceIds, ['large']);
    expect(backend.playedUrls, hasLength(1));
  });

  for (final id in ['uhd', 'stale']) {
    test('explicit forbidden/stale Delta ID $id never resolves', () async {
      final item = _PolicyItem('a', SipflixServers.delta.recordId, [
        _source('uhd', 3840, 100),
        _source('hd', 1920, 900),
      ]);
      await manager.playItems([item], mediaSourceId: id);
      expect(resolver.calls, 0);
      expect(backend.playedUrls, isEmpty);
      expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
    });
  }

  test('Delta forbidden-only default refuses before resolver', () async {
    final item = _PolicyItem('a', SipflixServers.delta.recordId, [
      _source('uhd', 3840, 100),
    ]);
    await manager.playItems([item]);
    expect(resolver.calls, 0);
    expect(backend.playedUrls, isEmpty);
    expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
  });

  for (final method in [
    StreamPlayMethod.directPlay,
    StreamPlayMethod.transcode,
  ]) {
    test('thin Delta item rejects resolved UHD for $method', () async {
      final item = _PolicyItem('a', SipflixServers.delta.recordId, []);
      resolver.playMethod = method;
      resolver.mediaStreams = [
        {'Type': 'Video', 'Width': 3840, 'Height': 2160},
      ];
      await manager.playItems([item]);
      expect(resolver.calls, 1);
      expect(backend.playedUrls, isEmpty);
      expect(service.transcodingStops, hasLength(1));
      expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
    });
  }

  test('thin item preparation chooses hydrated smallest version', () async {
    final thin = _PolicyItem('a', SipflixServers.alphaV2.recordId, []);
    manager.sourceSelectionPolicy = (item, selected) async {
      final hydrated = _PolicyItem(item.id, item.serverId, [
        _source('big', 1920, 900),
        _source('small', 1280, 100),
      ]);
      return (
        item: hydrated,
        mediaSourceId:
            selected ??
            Sipflix4kPolicy.defaultSource(
              hydrated.mediaSources,
              serverRef: hydrated.serverId,
              cannotPlay4k: false,
            )?['Id']?.toString(),
      );
    };
    await manager.playItems([thin]);
    expect(resolver.requestedMediaSourceIds, ['small']);
    expect(backend.playedUrls, hasLength(1));
  });

  test('stopped session cannot resume after slow source preparation', () async {
    final gate = Completer<void>();
    final item = _PolicyItem('a', SipflixServers.alphaV2.recordId, []);
    manager.sourceSelectionPolicy = (item, selected) async {
      await gate.future;
      return (item: item, mediaSourceId: 'small');
    };
    final starting = manager.playItems([item]);
    await Future<void>.delayed(Duration.zero);
    await manager.stop();
    gate.complete();
    await starting;
    expect(resolver.calls, 0);
    expect(backend.playedUrls, isEmpty);
  });
}
