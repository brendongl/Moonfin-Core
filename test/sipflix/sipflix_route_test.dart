import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/sipflix/sipflix_connection_manager.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:server_core/server_core.dart';

// The route list and the pure route maths behind the Server Page toggle and the
// player's Server Route button. Applying a route touches live clients and the
// server store, so that half is verified on a device, not here.
void main() {
  Server serverAt(String address) => Server(
        id: SipflixServers.serverId,
        name: 'Sipflix',
        address: address,
        version: '4.9.5.0',
        serverType: ServerType.emby,
        setupCompleted: true,
        dateAdded: DateTime(2026),
      );

  group('route choices', () {
    test('offers CDN 1, CDN 2 and Direct, CDN 1 first', () {
      expect(
        SipflixServers.routeChoices.map((r) => r.id),
        ['cdn1', 'cdn2', 'direct'],
      );
      expect(SipflixServers.routeChoices.first.url, SipflixServers.serverUrl);
    });

    test('every route has a distinct https url', () {
      final urls = SipflixServers.routeChoices.map((r) => r.url).toSet();
      expect(urls.length, SipflixServers.routeChoices.length);
      for (final r in SipflixServers.routeChoices) {
        expect(r.url, startsWith('https://'));
      }
    });

    test('CDN 2 is the nebula edge, not the dead alphacdn2 name', () {
      expect(SipflixServers.cdn2Url, 'https://nebula.cdn2.d-crypt.io');
      expect(SipflixServers.cdn2Url, isNot(contains('alphacdn2')));
    });
  });

  group('currentRoute', () {
    test('reads the route back off the stored address', () {
      for (final route in SipflixServers.routeChoices) {
        expect(
          SipflixConnectionManager.currentRoute(serverAt(route.url)).id,
          route.id,
        );
      }
    });

    test('ignores a trailing slash', () {
      expect(
        SipflixConnectionManager.currentRoute(
          serverAt('${SipflixServers.directUrl}/'),
        ).id,
        'direct',
      );
    });

    test('falls back to CDN 1 for an address off the list', () {
      expect(
        SipflixConnectionManager.currentRoute(
          serverAt('https://somewhere.else.example'),
        ).id,
        'cdn1',
      );
    });
  });

  group('isSipflixServerRef', () {
    test('accepts the stored server id', () {
      expect(SipflixServers.isSipflixServerRef(SipflixServers.serverId), isTrue);
    });

    test('accepts any route URL, because items carry the base URL', () {
      for (final route in SipflixServers.routeChoices) {
        expect(SipflixServers.isSipflixServerRef(route.url), isTrue);
        expect(SipflixServers.isSipflixServerRef('${route.url}/'), isTrue);
      }
    });

    test('rejects another server', () {
      expect(
        SipflixServers.isSipflixServerRef('https://emby.example.com'),
        isFalse,
      );
      expect(SipflixServers.isSipflixServerRef('seerr'), isFalse);
      expect(SipflixServers.isSipflixServerRef(''), isFalse);
    });
  });

  group('nextRoute', () {
    test('cycles through every route and wraps', () {
      var route = SipflixServers.routeChoices.first;
      final seen = <String>[route.id];
      for (var i = 0; i < SipflixServers.routeChoices.length - 1; i++) {
        route = SipflixConnectionManager.nextRoute(route);
        seen.add(route.id);
      }
      expect(seen, ['cdn1', 'cdn2', 'direct']);
      expect(SipflixConnectionManager.nextRoute(route).id, 'cdn1');
    });
  });
}
