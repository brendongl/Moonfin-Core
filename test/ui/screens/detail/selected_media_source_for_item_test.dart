// Regression test for R1-C finding 1 ("selectedMediaSourceForItem returns a
// raw 4K mediaSourceId match without re-checking Sipflix4kPolicy"). The
// function used to look the requested id up in the unfiltered
// `item.mediaSources` list, so any caller that ever passes a 4K source's id
// on a fragile-decoder box (a stale selection restored from state, a deep
// link, a server-remembered "last played source") would get the 4K HEVC
// source handed straight to the player — the exact source class the
// Allwinner decoder crashes on. The fix routes the id lookup through
// Sipflix4kPolicy.selectableSources first.
//
// PlatformDetection reports no device hardware strings in the test runner,
// and Sipflix4kPolicy.isFragileHevcDecoder treats unknown hardware as
// fragile, so these tests exercise the fragile-decoder path by default.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart';

void main() {
  final hdSource = <String, dynamic>{
    'Id': 'hd-source',
    'Name': '1080p',
    'Size': 2000000000,
    'MediaStreams': [
      {'Type': 'Video', 'Width': 1920},
    ],
  };

  final uhdSource = <String, dynamic>{
    'Id': '4k-source',
    'Name': '4K',
    'Size': 20000000000,
    'MediaStreams': [
      {'Type': 'Video', 'Width': 3840},
    ],
  };

  AggregatedItem itemWith(List<Map<String, dynamic>> sources) =>
      AggregatedItem(
        id: 'item-1',
        serverId: 'server-1',
        rawData: {'MediaSources': sources},
      );

  test(
    'a selectedMediaSourceId naming the 4K source never returns it on a fragile box',
    () {
      final item = itemWith([uhdSource, hdSource]);

      final result = selectedMediaSourceForItem(item, '4k-source');

      expect(result, isNotNull);
      expect(result!['Id'], isNot('4k-source'));
      expect(result['Id'], 'hd-source');
    },
  );

  test('a selectedMediaSourceId naming the HD source still returns it', () {
    final item = itemWith([uhdSource, hdSource]);

    final result = selectedMediaSourceForItem(item, 'hd-source');

    expect(result, isNotNull);
    expect(result!['Id'], 'hd-source');
  });

  test('no selection falls back to the policy default (smallest HD)', () {
    final item = itemWith([uhdSource, hdSource]);

    final result = selectedMediaSourceForItem(item, null);

    expect(result, isNotNull);
    expect(result!['Id'], 'hd-source');
  });

  test(
    '4K-only item still returns something (refusal happens elsewhere, not a crash)',
    () {
      final item = itemWith([uhdSource]);

      final result = selectedMediaSourceForItem(item, '4k-source');

      expect(result, isNotNull);
      expect(result!['Id'], '4k-source');
    },
  );

  test('empty mediaSources returns null', () {
    final item = itemWith(const []);

    expect(selectedMediaSourceForItem(item, 'anything'), isNull);
  });
}
