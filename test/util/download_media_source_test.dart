import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/download_quality.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/download_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shaped like the server responses for a movie with a 1080p and a 720p
/// version. Jellyfin's source Id is the version's own item id. Emby
/// prefixes it and names the item in ItemId. The top level MediaStreams are
/// the item's own file, which on Emby isn't its default first source.
Map<String, dynamic> _source(
  String id, {
  String? itemId,
  required String container,
  required int size,
  required int subtitleIndex,
}) => {
  'Id': id,
  'ItemId': ?itemId,
  'Container': container,
  'Size': size,
  'MediaStreams': [
    {'Type': 'Video', 'Index': 0},
    {'Type': 'Subtitle', 'Index': subtitleIndex},
  ],
};

AggregatedItem _movie(
  String id,
  List<Map<String, dynamic>> sources, {
  int ownSource = 0,
}) => AggregatedItem(
  id: id,
  serverId: 's1',
  rawData: {
    'Id': id,
    'Name': 'Version Test',
    'Type': 'Movie',
    'MediaSources': sources,
    'MediaStreams': sources[ownSource]['MediaStreams'],
  },
);

final _jellyfin = _movie('jf1080', [
  _source('jf1080', container: 'mp4', size: 55122, subtitleIndex: 2),
  _source('jf720', container: 'webm', size: 7785066, subtitleIndex: 3),
]);

final _emby = _movie('23', [
  _source(
    'mediasource_24',
    itemId: '24',
    container: 'webm',
    size: 7785066,
    subtitleIndex: 3,
  ),
  _source(
    'mediasource_23',
    itemId: '23',
    container: 'mp4',
    size: 55122,
    subtitleIndex: 2,
  ),
], ownSource: 1);

int _subtitleIndex(AggregatedItem item) =>
    item.mediaStreams.firstWhere((s) => s['Type'] == 'Subtitle')['Index']
        as int;

void main() {
  group('withPreferredMediaSource', () {
    test('moves the picked version to the front', () {
      final picked = withPreferredMediaSource(_jellyfin, 'jf720');

      expect(picked.mediaSources.map((s) => s['Id']), ['jf720', 'jf1080']);
      expect(picked.id, 'jf1080');
      expect(picked.serverId, 's1');
    });

    test('size and the top level streams follow the picked version', () {
      final picked = withPreferredMediaSource(_jellyfin, 'jf720');

      expect(
        estimateDownloadSizeBytes(picked, DownloadQuality.original),
        7785066,
      );
      expect(_subtitleIndex(picked), 3);
    });

    test('an Emby default pick takes its streams from the first source', () {
      final picked = withPreferredMediaSource(_emby, 'mediasource_24');

      expect(picked.mediaSources.map((s) => s['Id']), [
        'mediasource_24',
        'mediasource_23',
      ]);
      expect(_subtitleIndex(_emby), 2);
      expect(_subtitleIndex(picked), 3);
    });

    test('leaves the item alone for a single source or an unknown id', () {
      final single = _movie('solo', [
        _source('solo', container: 'mkv', size: 1, subtitleIndex: 2),
      ]);

      expect(
        identical(withPreferredMediaSource(single, 'solo'), single),
        isTrue,
      );
      expect(
        identical(withPreferredMediaSource(_jellyfin, 'missing'), _jellyfin),
        isTrue,
      );
      expect(
        identical(withPreferredMediaSource(_jellyfin, null), _jellyfin),
        isTrue,
      );
    });

    test("doesn't change the original item", () {
      withPreferredMediaSource(_emby, 'mediasource_23');

      expect(_emby.mediaSources.first['Id'], 'mediasource_24');
    });
  });

  group('mediaSourceItemId', () {
    test('a Jellyfin version is served by its source id', () {
      expect(mediaSourceItemId(_jellyfin), 'jf1080');
      expect(
        mediaSourceItemId(withPreferredMediaSource(_jellyfin, 'jf720')),
        'jf720',
      );
    });

    test('an Emby version is served by its ItemId', () {
      expect(mediaSourceItemId(_emby), '24');
      expect(
        mediaSourceItemId(withPreferredMediaSource(_emby, 'mediasource_23')),
        '23',
      );
    });

    test('a single-version item keeps its own id', () {
      final single = _movie('solo', [
        _source(
          'mediasource_99',
          itemId: '99',
          container: 'mkv',
          size: 1,
          subtitleIndex: 2,
        ),
      ]);

      expect(mediaSourceItemId(single), 'solo');
      expect(
        mediaSourceItemId(
          AggregatedItem(id: 'bare', serverId: 's1', rawData: const {}),
        ),
        'bare',
      );
    });
  });

  group('transcodeAudioStreamIndex', () {
    late UserPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const {});
      final store = PreferenceStore();
      await store.init();
      prefs = UserPreferences(store);
    });

    List<Map<String, dynamic>> audioTracks() => [
      {'Type': 'Video', 'Index': 0},
      {'Type': 'Audio', 'Index': 1, 'Language': 'fre', 'IsDefault': true},
      {'Type': 'Audio', 'Index': 2, 'Language': 'jpn'},
    ];

    final audioTest = _movie('audio', [
      {'Id': 'audio', 'MediaStreams': audioTracks()},
    ]);

    test('keeps the track picked on the details page', () {
      expect(transcodeAudioStreamIndex(audioTest, 2, prefs), 2);
    });

    test('follows the default audio language with no pick', () async {
      await prefs.set(UserPreferences.defaultAudioLanguage, 'jpn');

      expect(transcodeAudioStreamIndex(audioTest, null, prefs), 2);
    });

    test('takes the flagged default over the first track', () {
      final item = _movie('show', [
        {
          'Id': 'show',
          'MediaStreams': [
            {'Type': 'Audio', 'Index': 1, 'Language': 'fre'},
            {'Type': 'Audio', 'Index': 2, 'Language': 'jpn', 'IsDefault': true},
          ],
        },
      ]);

      expect(transcodeAudioStreamIndex(item, null, prefs), 2);
    });

    test("ignores a pick the version doesn't have", () async {
      await prefs.set(UserPreferences.defaultAudioLanguage, 'jpn');

      expect(transcodeAudioStreamIndex(audioTest, 5, prefs), 2);
    });

    test("reads the first source's tracks over the top level ones", () async {
      await prefs.set(UserPreferences.defaultAudioLanguage, 'jpn');
      final item = AggregatedItem(
        id: 'other',
        serverId: 's1',
        rawData: {
          'MediaSources': [
            {'Id': 'first', 'MediaStreams': audioTracks()},
          ],
          'MediaStreams': [
            {'Type': 'Audio', 'Index': 1, 'Language': 'jpn'},
          ],
        },
      );

      expect(transcodeAudioStreamIndex(item, null, prefs), 2);
    });
  });
}
