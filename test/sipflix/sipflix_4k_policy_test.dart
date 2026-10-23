import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_4k_policy.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

class _Item {
  _Item(this.mediaSources, [this.serverId = '']);
  final String serverId;
  final List<Map<String, dynamic>> mediaSources;
}

Map<String, dynamic> _source(String id, int width, [int? size]) => {
  'Id': id,
  if (size != null) 'Size': size,
  'MediaStreams': [
    {'Type': 'Video', 'Width': width, 'Height': width * 9 ~/ 16},
    {'Type': 'Audio'},
  ],
};

void main() {
  test('Silo fragile codec veto covers selected and resolved thin sources', () {
    final server = SipflixServers.dumb.recordId;
    for (final codec in ['hevc', 'h265', 'HEVC', 'av1', 'av01']) {
      final streams = <Map<String, dynamic>>[
        {'Type': 'Video', 'Width': 1920, 'Codec': codec},
      ];
      final item = _Item([
        {'Id': 'unsafe', 'MediaStreams': streams},
      ], server);
      expect(
        Sipflix4kPolicy.sourceRefusal(item, [], 'unsafe', fragileDecoder: true),
        Sipflix4kPolicy.unsupportedSiloCodecMessage,
      );
      expect(
        Sipflix4kPolicy.sourceRefusal(
          _Item([], server),
          streams,
          'unsafe',
          fragileDecoder: true,
        ),
        Sipflix4kPolicy.unsupportedSiloCodecMessage,
      );
      expect(
        Sipflix4kPolicy.sourceRefusal(
          item,
          streams,
          'unsafe',
          fragileDecoder: false,
        ),
        isNull,
      );
      expect(
        Sipflix4kPolicy.sourceRefusal(
          _Item(item.mediaSources, SipflixServers.alphaV2.recordId),
          streams,
          'unsafe',
          fragileDecoder: true,
        ),
        isNull,
      );
    }
  });
  test('Silo safe explicit H264 is allowed beside unsafe alternative', () {
    final item = _Item([
      {
        'Id': 'hevc',
        'MediaStreams': [
          {'Type': 'Video', 'Codec': 'hevc'},
        ],
      },
      {
        'Id': 'safe',
        'MediaStreams': [
          {'Type': 'Video', 'Codec': 'h264'},
        ],
      },
    ], SipflixServers.dumb.recordId);
    expect(
      Sipflix4kPolicy.sourceRefusal(item, [], 'safe', fragileDecoder: true),
      isNull,
    );
    expect(
      Sipflix4kPolicy.sourceRefusal(item, [], null, fragileDecoder: true),
      Sipflix4kPolicy.unsupportedSiloCodecMessage,
    );
  });
  group('server version policy', () {
    final alpha = SipflixServers.alphaV2.recordId;
    final delta = SipflixServers.delta.recordId;
    test('Alpha chooses smallest even on capable hardware and every route', () {
      for (final ref in [
        alpha,
        ...SipflixServers.alphaV2.routes.map((r) => r.url),
      ]) {
        expect(
          Sipflix4kPolicy.defaultSource(
            [_source('large', 1920, 9000), _source('small', 3840, 1000)],
            cannotPlay4k: false,
            serverRef: ref,
          )?['Id'],
          'small',
        );
      }
    });
    test('Delta strips >1080p and cropped UHD on every route', () {
      for (final ref in [
        delta,
        ...SipflixServers.delta.routes.map((r) => r.url),
      ]) {
        final cropped = _source('cropped', 3840, 100)
          ..['MediaStreams'][0]['Height'] = 1000;
        expect(
          Sipflix4kPolicy.selectableSources(
            [_source('1440p', 2560, 200), cropped, _source('hd', 1920, 900)],
            cannotPlay4k: false,
            serverRef: ref,
          ).map((s) => s['Id']),
          ['hd'],
        );
      }
    });
    test('Delta UHD-only never falls back to forbidden source', () {
      final sources = [_source('uhd', 3840, 100)];
      expect(
        Sipflix4kPolicy.selectableSources(sources, serverRef: delta),
        isEmpty,
      );
      expect(Sipflix4kPolicy.defaultSource(sources, serverRef: delta), isNull);
      expect(
        Sipflix4kPolicy.sourceRefusal(_Item(sources, delta), [], null),
        Sipflix4kPolicy.deltaHdOnlyMessage,
      );
    });
    test('unknown and invalid sizes lose, equal sizes preserve order', () {
      final sources = [
        _source('missing', 1920),
        _source('zero', 1920, 0),
        _source('nan', 1920)..['Size'] = double.nan,
        _source('infinite', 1920)..['Size'] = double.infinity,
        _source('a', 1920, 100),
        _source('b', 1280, 100),
      ];
      expect(
        Sipflix4kPolicy.defaultSource(sources, serverRef: alpha)?['Id'],
        'a',
      );
    });
    test('manual allowed ID stays allowed, forbidden or stale ID refuses', () {
      final item = _Item([_source('uhd', 3840), _source('hd', 1920)], delta);
      expect(Sipflix4kPolicy.sourceRefusal(item, [], 'hd'), isNull);
      for (final id in ['uhd', 'stale']) {
        expect(
          Sipflix4kPolicy.sourceRefusal(item, [], id),
          Sipflix4kPolicy.deltaHdOnlyMessage,
        );
      }
    });
    test('thin Delta item checked against resolved streams', () {
      final item = _Item([], delta);
      expect(Sipflix4kPolicy.sourceRefusal(item, [], null), isNull);
      expect(
        Sipflix4kPolicy.sourceRefusal(item, [
          {'Type': 'Video', 'Height': 1440, 'Width': 2560},
        ], 'resolved'),
        Sipflix4kPolicy.deltaHdOnlyMessage,
      );
      expect(
        Sipflix4kPolicy.sourceRefusal(item, [
          {'Type': 'Video', 'Height': 1080, 'Width': 1920},
        ], 'resolved'),
        isNull,
      );
    });
    test('other servers retain capable-device ordering', () {
      final sources = [
        _source('first', 3840, 900),
        _source('small', 1920, 100),
      ];
      for (final ref in [
        SipflixServers.iDuck.recordId,
        'https://s.sipflix.net',
        'unknown',
      ]) {
        expect(
          Sipflix4kPolicy.defaultSource(
            sources,
            serverRef: ref,
            cannotPlay4k: false,
          )?['Id'],
          'first',
        );
      }
    });
    test('Alpha fragile decoder protection survives smallest preference', () {
      expect(
        Sipflix4kPolicy.defaultSource(
          [_source('uhd', 3840, 10), _source('hd', 1920, 900)],
          serverRef: alpha,
          cannotPlay4k: true,
        )?['Id'],
        'hd',
      );
    });
  });

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
      final item = _Item([
        _source('a', 3840)..['MediaStreams'][0]['Height'] = 1600,
      ]);
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
      expect(
        Sipflix4kPolicy.directPlayOnly(Object(), streams, null),
        isNotNull,
      );
    });

    test('an item without sources is not refused', () {
      expect(Sipflix4kPolicy.directPlayOnly(Object(), const [], null), isNull);
    });

    test('a mediaSourceId that matches none of the item\'s sources is '
        'refused, not waved through (fix: R4-H1/H3 operator rule — 4K must '
        'never transcode on any device, and data drift must not be the '
        'loophole)', () {
      final item = _Item([_source('hd', 1920)]);
      expect(
        Sipflix4kPolicy.directPlayOnly(item, const [], 'stale-id'),
        isNotNull,
      );
    });
  });

  group('version choice on a box that cannot play 4K', () {
    final uhd = _source('uhd', 3840);
    final hd = _source('hd', 1920);
    final sd = _source('sd', 1280);

    test('4K versions are hidden when an HD one exists', () {
      final out = Sipflix4kPolicy.selectableSources([
        uhd,
        hd,
        sd,
      ], cannotPlay4k: true);
      expect(out.map((s) => s['Id']), ['hd', 'sd']);
    });

    test('a 4K-only title is kept so the refusal still shows', () {
      final out = Sipflix4kPolicy.selectableSources([uhd], cannotPlay4k: true);
      expect(out.map((s) => s['Id']), ['uhd']);
    });

    test('capable boxes see everything', () {
      final out = Sipflix4kPolicy.selectableSources([
        uhd,
        hd,
      ], cannotPlay4k: false);
      expect(out.length, 2);
    });

    test('default is the smallest non-4K file, never the 4K first entry', () {
      final big = _source('big', 1920, 9000);
      final small = _source('small', 1280, 2000);
      final mid = _source('mid', 1920, 4000);
      final huge = _source('uhd', 3840, 1000);
      expect(
        Sipflix4kPolicy.defaultSource([
          huge,
          big,
          small,
          mid,
        ], cannotPlay4k: true)?['Id'],
        'small',
      );
    });

    test(
      'missing Size falls back to the first HD version, sized beats unsized',
      () {
        expect(
          Sipflix4kPolicy.defaultSource([
            uhd,
            sd,
            hd,
          ], cannotPlay4k: true)?['Id'],
          'sd',
        );
        expect(
          Sipflix4kPolicy.defaultSource([
            uhd,
            _source('a', 1920),
            _source('b', 1920, 500),
          ], cannotPlay4k: true)?['Id'],
          'b',
        );
      },
    );

    test('4K-only stays 4K', () {
      expect(
        Sipflix4kPolicy.defaultSource([uhd], cannotPlay4k: true)?['Id'],
        'uhd',
      );
    });

    test('capable boxes keep the server order', () {
      expect(
        Sipflix4kPolicy.defaultSource([uhd, hd], cannotPlay4k: false)?['Id'],
        'uhd',
      );
      expect(Sipflix4kPolicy.defaultSource([], cannotPlay4k: true), isNull);
    });
  });

  test('refusals are recognised so they are not reported as faults', () {
    expect(Sipflix4kPolicy.isRefusal(Sipflix4kPolicy.refusalMessage), isTrue);
    expect(
      Sipflix4kPolicy.isRefusal(Sipflix4kPolicy.unsupportedDeviceMessage),
      isTrue,
    );
    expect(
      Sipflix4kPolicy.isRefusal(Sipflix4kPolicy.onlyAvailableIn4kMessage),
      isTrue,
    );
    expect(Sipflix4kPolicy.isRefusal('Playback failed.'), isFalse);
    expect(Sipflix4kPolicy.isRefusal(null), isFalse);
  });

  group('messageForUnsupportedDevice (R1-B: "Barreda" 4K-only dead end)', () {
    final uhd = _source('uhd', 3840);
    final hd = _source('hd', 1920);

    test('a 4K-only title gets the plain "can\'t play this" message', () {
      expect(
        Sipflix4kPolicy.messageForUnsupportedDevice([uhd]),
        Sipflix4kPolicy.onlyAvailableIn4kMessage,
      );
    });

    test(
      'a title with a real HD alternative keeps the "choose HD" message',
      () {
        expect(
          Sipflix4kPolicy.messageForUnsupportedDevice([uhd, hd]),
          Sipflix4kPolicy.unsupportedDeviceMessage,
        );
      },
    );

    test('no source list falls back to the normal message', () {
      expect(
        Sipflix4kPolicy.messageForUnsupportedDevice(null),
        Sipflix4kPolicy.unsupportedDeviceMessage,
      );
      expect(
        Sipflix4kPolicy.messageForUnsupportedDevice(const []),
        Sipflix4kPolicy.unsupportedDeviceMessage,
      );
    });
  });

  group('hasPlayableAlternative', () {
    test('false when every source is 4K', () {
      expect(
        Sipflix4kPolicy.hasPlayableAlternative([_source('uhd', 3840)]),
        isFalse,
      );
    });

    test('true when an HD source exists alongside 4K', () {
      expect(
        Sipflix4kPolicy.hasPlayableAlternative([
          _source('uhd', 3840),
          _source('hd', 1920),
        ]),
        isTrue,
      );
    });
  });
}
