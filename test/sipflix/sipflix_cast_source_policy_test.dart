import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/sipflix/sipflix_cast_source_policy.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:moonfin/data/services/cast/remote_session_cast_provider.dart';
import 'package:moonfin/data/services/cast/cast_target.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/util/download_utils.dart';

class _Items extends Fake implements ItemsApi {
  Map<String, dynamic> raw = {};
  int calls = 0;
  @override
  Future<Map<String, dynamic>> getItem(
    String id, {
    String? mediaSourceId,
    String? fields,
  }) async {
    calls++;
    return raw;
  }
}

class _Playback extends Fake implements PlaybackApi {
  final stops = <String?>[];
  @override
  Future<void> stopActiveEncodings({
    required String deviceId,
    String? playSessionId,
  }) async {
    stops.add(playSessionId);
  }
}

class _Sessions extends Fake implements SessionApi {
  final sources = <String?>[];
  @override
  Future<void> sendPlayCommand(
    String sessionId, {
    required String playCommand,
    required List<String> itemIds,
    int? startPositionTicks,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startIndex,
  }) async {
    sources.add(mediaSourceId);
  }
}

class _Factory extends Fake implements MediaServerClientFactory {
  _Factory(this.client);
  final MediaServerClient client;
  @override
  MediaServerClient? getClientIfExists(String serverId) => client;
}

class _Client extends Fake implements MediaServerClient {
  @override
  final _Sessions sessionApi = _Sessions();
  @override
  final _Items itemsApi = _Items();
  @override
  final _Playback playbackApi = _Playback();
  @override
  DeviceInfo get deviceInfo => const DeviceInfo(
    id: 'test',
    name: 'test',
    appName: 'test',
    appVersion: '1',
  );
}

Map<String, dynamic> source(String id, int width, int size) => {
  'Id': id,
  'ItemId': id,
  'Size': size,
  'MediaStreams': [
    {'Type': 'Video', 'Width': width, 'Height': width * 9 ~/ 16},
  ],
};
AggregatedItem item(String server, List<Map<String, dynamic>> sources) =>
    AggregatedItem(
      id: 'title',
      serverId: server,
      rawData: {'Type': 'Movie', 'MediaSources': sources},
    );

void main() {
  const target = CastTarget(
    id: 'remote',
    kind: CastTargetKind.jellyfinSession,
    title: 'Test',
  );
  test('remote session cannot enqueue versions it cannot enforce', () async {
    final client = _Client();
    final provider = RemoteSessionCastProvider(_Factory(client));
    final a = item(SipflixServers.delta.recordId, [source('hd', 1920, 100)]);
    await expectLater(
      provider.playToTarget(target, item: a, queueItems: [a, a]),
      throwsStateError,
    );
    expect(client.sessionApi.sources, isEmpty);
  });
  test('remote session sends selected HD source explicitly', () async {
    final client = _Client();
    final provider = RemoteSessionCastProvider(_Factory(client));
    final a = item(SipflixServers.delta.recordId, [
      source('uhd', 3840, 100),
      source('hd', 1920, 900),
    ]);
    await provider.playToTarget(target, item: a);
    expect(client.sessionApi.sources, ['hd']);
  });

  test(
    'download helper defaults to smallest Alpha and keeps chosen source',
    () {
      final a = item(SipflixServers.alphaV2.recordId, [
        source('large', 1920, 900),
        source('small', 1280, 100),
      ]);
      expect(
        withPreferredMediaSource(a, null).mediaSources.first['Id'],
        'small',
      );
      expect(
        withPreferredMediaSource(a, 'large').mediaSources.first['Id'],
        'large',
      );
    },
  );
  test('download helper filters Delta and refuses explicit forbidden and unknown-only metadata', () {
    final a = item(SipflixServers.delta.recordId, [
      source('uhd', 3840, 100),
      source('hd', 1920, 900),
    ]);
    expect(withPreferredMediaSource(a, null).mediaSources.map((s) => s['Id']), [
      'hd',
    ]);
    expect(() => withPreferredMediaSource(a, 'uhd'), throwsStateError);
    expect(() => withPreferredMediaSource(a, 'stale'), throwsStateError);
    expect(
      () => withPreferredMediaSource(
        item(SipflixServers.delta.recordId, []),
        null,
      ),
      throwsStateError,
    );
  });
  test('thin cast item hydrates and names permitted source', () async {
    final client = _Client();
    client.itemsApi.raw = {
      'MediaSources': [source('uhd', 3840, 100), source('hd', 1920, 900)],
    };
    final prepared = await prepareSipflixCastSource(
      client,
      item(SipflixServers.delta.recordId, []),
      null,
    );
    expect(prepared.sourceId, 'hd');
    expect(prepared.item.mediaSources, hasLength(1));
    expect(client.itemsApi.calls, 1);
  });
  test('cast refuses explicit UHD before resolving', () async {
    final client = _Client();
    final a = item(SipflixServers.delta.recordId, [
      source('uhd', 3840, 100),
      source('hd', 1920, 900),
    ]);
    await expectLater(
      prepareSipflixCastSource(client, a, 'uhd'),
      throwsStateError,
    );
    expect(client.itemsApi.calls, 0);
  });
  test(
    'resolved forbidden stream is stopped even if server ignored requested HD',
    () async {
      final client = _Client();
      final a = item(SipflixServers.delta.recordId, [source('hd', 1920, 900)]);
      await expectLater(
        verifySipflixCastResolution(
          client,
          a,
          StreamResolutionResult(
            streamUrl: 'https://example.invalid',
            mediaSourceId: 'hd',
            playSessionId: 'session',
            playMethod: StreamPlayMethod.transcode,
            mediaStreams: [
              {'Type': 'Video', 'Width': 3840, 'Height': 2160},
            ],
          ),
        ),
        throwsStateError,
      );
      expect(client.playbackApi.stops, ['session']);
    },
  );
  test('non-Sipflix casts retain upstream behavior and skip fetch', () async {
    final client = _Client();
    final a = item('other', []);
    final prepared = await prepareSipflixCastSource(client, a, 'explicit');
    expect(prepared.item, same(a));
    expect(prepared.sourceId, 'explicit');
    expect(client.itemsApi.calls, 0);
  });
}
