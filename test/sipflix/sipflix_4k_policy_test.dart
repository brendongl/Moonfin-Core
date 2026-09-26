import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_4k_policy.dart';

class _Item {
  _Item(this.mediaSources);
  final List<Map<String, dynamic>> mediaSources;
}

Map<String, dynamic> _source(String id, int width) => {
      'Id': id,
      'MediaStreams': [
        {'Type': 'Video', 'Width': width, 'Height': width * 9 ~/ 16},
        {'Type': 'Audio'},
      ],
    };

void main() {
  group('isFragileHevcHardware', () {
    bool fragile(String hardware, String board, String soc) =>
        Sipflix4kPolicy.isFragileHevcHardware(
          hardware: hardware,
          board: board,
          soc: soc,
        );

    test('Allwinner fleet boxes stay on H.264', () {
      expect(fragile('sun50iw9p1', 'apollo', 'H313'), isTrue);
      expect(fragile('sun50iw9p1', 'apollo', 'H618'), isTrue);
      expect(fragile('', 'apollo', ''), isTrue);
    });

    test('Shield and Amlogic boxes get HEVC', () {
      expect(fragile('darcy', 'darcy', ''), isFalse);
      expect(fragile('amlogic', 's7', 'S905Y4'), isFalse);
    });
  });

  group('directPlayOnly', () {
    test('a 4K source may only direct play', () {
      final item = _Item([_source('a', 3840)]);
      expect(Sipflix4kPolicy.directPlayOnly(item, const [], null), isNotNull);
    });

    test('scope-cropped UHD still counts as 4K', () {
      final item = _Item([_source('a', 3840)..['MediaStreams'][0]['Height'] = 1600]);
      expect(Sipflix4kPolicy.directPlayOnly(item, const [], 'a'), isNotNull);
    });

    test('an HD source may transcode', () {
      final item = _Item([_source('a', 1920)]);
      expect(Sipflix4kPolicy.directPlayOnly(item, const [], null), isNull);
    });

    test('only the version being played counts', () {
      final item = _Item([_source('uhd', 3840), _source('hd', 1920)]);
      expect(Sipflix4kPolicy.directPlayOnly(item, const [], 'hd'), isNull);
      expect(Sipflix4kPolicy.directPlayOnly(item, const [], 'uhd'), isNotNull);
      expect(Sipflix4kPolicy.directPlayOnly(item, const [], null), isNotNull);
    });

    test('resolved streams catch a thin item payload', () {
      final streams = [
        {'Type': 'Video', 'Width': 3840},
      ];
      expect(Sipflix4kPolicy.directPlayOnly(Object(), streams, null), isNotNull);
    });

    test('an item without sources is not refused', () {
      expect(Sipflix4kPolicy.directPlayOnly(Object(), const [], null), isNull);
    });
  });

  test('refusals are recognised so they are not reported as faults', () {
    expect(Sipflix4kPolicy.isRefusal(Sipflix4kPolicy.refusalMessage), isTrue);
    expect(
      Sipflix4kPolicy.isRefusal(Sipflix4kPolicy.unsupportedDeviceMessage),
      isTrue,
    );
    expect(Sipflix4kPolicy.isRefusal('Playback failed.'), isFalse);
    expect(Sipflix4kPolicy.isRefusal(null), isFalse);
  });
}
