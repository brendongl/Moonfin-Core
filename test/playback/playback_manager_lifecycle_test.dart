import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

class _Backend extends PlayerBackend {
  final played = <String>[];
  final errors = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Duration position = Duration.zero;
  @override
  Duration get duration => const Duration(hours: 1);
  @override
  Duration get buffer => Duration.zero;
  @override
  bool get isPlaying => played.isNotEmpty;
  @override
  bool get isBuffering => false;
  @override
  double get playbackSpeed => 1;
  @override
  bool get supportsRuntimeTrackSelection => false;
  @override
  bool get canRenderBitmapSubtitles => false;
  @override
  bool get requiresStartupMediaReadyCheck => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<bool> get bufferingStream => const Stream.empty();
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get errorStream => errors.stream;
  @override
  Map<String, dynamic> getDeviceProfile({
    bool useProgressiveTranscode = false,
  }) => {};
  @override
  Future<void> play(
    dynamic item, {
    Duration startPosition = Duration.zero,
  }) async {
    played.add(item.toString());
    position = startPosition;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> seekTo(Duration value) async {
    position = value;
  }

  @override
  void dispose() {
    unawaited(errors.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Resolver extends MediaStreamResolver {
  final requests = <Invocation>[];
  Future<StreamResolutionResult> Function(Invocation)? handler;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    requests.add(invocation);
    return handler?.call(invocation) ??
        Future.value(
          StreamResolutionResult(
            streamUrl:
                'https://example.test/${invocation.positionalArguments[0]['Id']}',
            mediaSourceId: 'source',
            playMethod: StreamPlayMethod.directPlay,
          ),
        );
  }
}

class _Service extends PlayerService {
  final stops = <Duration>[];
  @override
  Future<void> onPlaybackStop(
    dynamic item,
    StreamResolutionResult resolution,
    Duration position,
  ) async {
    stops.add(position);
  }

  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  late PlaybackManager manager;
  late _Backend backend;
  late _Resolver resolver;
  late _Service service;
  const a = {'Id': 'a'};
  const b = {'Id': 'b'};
  setUp(() {
    backend = _Backend();
    resolver = _Resolver();
    service = _Service();
    manager = PlaybackManager()
      ..setBackend(backend)
      ..setResolver(resolver)
      ..setPlayerService(service);
  });
  tearDown(() => manager.dispose());

  test('remote stop ends the player session and preserves resume position', () async {
    var ended = 0;
    manager.sessionEndedStream.listen((_) => ended++);
    await manager.playItems([a]);
    await manager.seekTo(const Duration(minutes: 14));
    await manager.stop(userInitiated: false, notifySessionEnded: true);
    await Future<void>.delayed(Duration.zero);
    expect(ended, 1);
    expect(manager.queueService.currentItem, isNull);
    expect(service.stops, [const Duration(minutes: 14)]);
    await manager.playItems([b]);
    expect(manager.queueService.currentItem, b);
  });

  test('ordinary teardown does not close the player route', () async {
    var ended = 0;
    manager.sessionEndedStream.listen((_) => ended++);
    await manager.playItems([a]);
    await manager.stop(userInitiated: false);
    await Future<void>.delayed(Duration.zero);
    expect(ended, 0);
  });

  test('404 preserves selected source without claiming the file is missing', () async {
    await manager.playItems([a]);
    final source = manager.currentResolution!.mediaSourceId;
    backend.errors.add({'event': 'error', 'httpStatus': 404, 'message': 'Source error'});
    await Future<void>.delayed(Duration.zero);
    expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
    expect(manager.bringupState.httpStatus, 404);
    expect(manager.bringupState.mediaSourceId, source);
    expect(manager.bringupState.error, contains('stream is unavailable'));
    expect(manager.bringupState.error, isNot(contains('no longer available')));
  });

  test('a PlaybackInfo that never answers fails with a plain message', () {
    fakeAsync((async) {
      resolver.handler = (_) => Completer<StreamResolutionResult>().future;
      Object? thrown;
      manager.playItems([a]).catchError((Object e) => thrown = e);
      async.elapse(PlaybackManager.resolveDeadline + const Duration(seconds: 1));
      expect(thrown, isA<TimeoutException>());
      expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
      expect(
        manager.bringupState.error,
        PlaybackManager.resolveTimeoutMessage,
      );
      expect(backend.played, isEmpty);
    });
  });

  test('stop during preflight never starts the abandoned item', () async {
    final entered = Completer<void>();
    final preflight = Completer<PlaybackPreflightResult?>();
    manager.preflightHook = (_) {
      entered.complete();
      return preflight.future;
    };
    final playing = manager.playItems([a]);
    await entered.future;
    expect(manager.bringupState.phase, PlaybackBringupPhase.resolving);
    await manager.stop();
    preflight.complete(null);
    await playing;
    expect(backend.played, isEmpty);
    expect(resolver.requests, isEmpty);
  });

  test(
    'next during preflight cannot let the old item replace the next episode',
    () async {
      final entered = Completer<void>();
      final preflight = Completer<PlaybackPreflightResult?>();
      manager.preflightHook = (item) {
        if (item['Id'] == 'a') {
          entered.complete();
          return preflight.future;
        }
        return Future.value(null);
      };
      final playing = manager.playItems([a, b]);
      await entered.future;
      await manager.next();
      preflight.complete(null);
      await playing;
      expect(resolver.requests.map((r) => r.positionalArguments[0]['Id']), [
        'b',
      ]);
      expect(backend.played, hasLength(1));
    },
  );

  test(
    'an abandoned preflight cannot overwrite the next episode bitrate',
    () async {
      final entered = Completer<void>();
      final preflight = Completer<PlaybackPreflightResult?>();
      manager.setBitrateOverride(8);
      manager.preflightHook = (item) {
        if (item['Id'] == 'a') {
          entered.complete();
          return preflight.future;
        }
        return Future.value(const PlaybackPreflightResult(capMbps: 6));
      };
      final playing = manager.playItems([a, b]);
      await entered.future;
      await manager.next();
      preflight.complete(const PlaybackPreflightResult(capMbps: 1));
      await playing;
      expect(manager.maxBitrateOverrideMbps, 6);
    },
  );

  test(
    'resolve failure leaves a failed state instead of an endless spinner',
    () async {
      resolver.handler = (_) =>
          Future.error(StateError('connection unavailable'));
      await expectLater(manager.playItems([a]), throwsStateError);
      expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
      expect(manager.bringupState.error, contains('connection unavailable'));
    },
  );

  test(
    'a preempted resume reports the saved position instead of zero',
    () async {
      final entered = Completer<void>();
      final pending = Completer<StreamResolutionResult>();
      resolver.handler = (_) {
        entered.complete();
        return pending.future;
      };
      final playing = manager.playItems([
        a,
      ], startPosition: const Duration(minutes: 12));
      await entered.future;
      await manager.stop();
      pending.complete(
        const StreamResolutionResult(
          streamUrl: 'https://example.test/a',
          mediaSourceId: 'source',
          playMethod: StreamPlayMethod.directPlay,
        ),
      );
      await playing;
      expect(service.stops, [const Duration(minutes: 12)]);
      expect(backend.played, isEmpty);
    },
  );

  test('route restart retains direct play and the current position', () async {
    await manager.playItems([a]);
    await manager.seekTo(const Duration(minutes: 5));
    await manager.restartCurrentStream();
    final retry = resolver.requests.last;
    expect(retry.namedArguments[#enableDirectPlay], isTrue);
    expect(retry.namedArguments[#enableDirectStream], isTrue);
    expect(retry.namedArguments[#startTimeTicks], 3000000000);
  });
}
