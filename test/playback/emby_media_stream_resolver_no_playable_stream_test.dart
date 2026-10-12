import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';
import 'package:playback_emby/playback_emby.dart';
import 'package:server_core/server_core.dart';

/// R4-H3 §1.5: a media source whose server response said
/// `SupportsTranscoding: true` / `TranscodingUrl: null` (and neither
/// SupportsDirectPlay nor a usable SupportsDirectStream URL) used to fall
/// through `_resolveStreamUrl`'s last branch and get mislabeled as
/// `StreamPlayMethod.directPlay` with a raw `/stream` URL the server never
/// said was ready. [resolve] must now throw [NoPlayableStreamException]
/// instead, so the failure surfaces through the normal resolve-failure path
/// rather than opening a URL as if it had been cleared.
class _FakeItemsApi implements ItemsApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaybackApi implements PlaybackApi {
  _FakePlaybackApi(this.response);
  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> getPlaybackInfo(
    String itemId, {
    Map<String, dynamic>? requestBody,
    String? userId,
    int? startTimeTicks,
    bool waitForMediaProbe = false,
  }) async => response;

  @override
  String getStreamUrl(
    String itemId, {
    String? mediaSourceId,
    String? audioStreamIndex,
    String? subtitleStreamIndex,
    String? liveStreamId,
  }) =>
      'http://fake/Videos/$itemId/stream';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements MediaServerClient {
  _FakeClient(Map<String, dynamic> response)
      : _playbackApi = _FakePlaybackApi(response);

  final _FakePlaybackApi _playbackApi;
  final _itemsApi = _FakeItemsApi();

  @override
  PlaybackApi get playbackApi => _playbackApi;

  @override
  ItemsApi get itemsApi => _itemsApi;

  @override
  String? get accessToken => null;

  @override
  String get baseUrl => 'http://fake';

  @override
  String? get userId => 'user1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'SupportsTranscoding=true with no TranscodingUrl throws instead of '
    'mislabeling as directPlay',
    () async {
      final client = _FakeClient({
        'PlaySessionId': 'sess1',
        'MediaSources': [
          {
            'Id': 'src1',
            'SupportsDirectPlay': false,
            'SupportsDirectStream': false,
            'SupportsTranscoding': true,
            'TranscodingUrl': null,
          },
        ],
      });
      final resolver = EmbyMediaStreamResolver(client);

      await expectLater(
        resolver.resolve({'Id': 'item1'}),
        throwsA(isA<NoPlayableStreamException>()),
      );
    },
  );

  test('a normal transcode source still resolves to transcode', () async {
    final client = _FakeClient({
      'PlaySessionId': 'sess1',
      'MediaSources': [
        {
          'Id': 'src1',
          'SupportsDirectPlay': false,
          'SupportsDirectStream': false,
          'SupportsTranscoding': true,
          'TranscodingUrl': '/Videos/item1/master.m3u8?a=b',
        },
      ],
    });
    final resolver = EmbyMediaStreamResolver(client);

    final result = await resolver.resolve({'Id': 'item1'});
    expect(result.playMethod, StreamPlayMethod.transcode);
  });
}
