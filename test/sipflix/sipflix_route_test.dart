import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/sipflix/sipflix_connection_manager.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:server_core/server_core.dart';

// The route list and the pure route maths behind the Server Page toggle and the
// player's Server Route button. Applying a route touches live clients and the
// server store, so that half is verified on a device, not here.
Server recordOf(SipflixServerDef def, String address) => Server(
      id: def.recordId,
      name: def.name,
      address: address,
      version: def.version,
      serverType: ServerType.emby,
      setupCompleted: true,
      dateAdded: DateTime(2026),
    );

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

  final alpha = serverAt(SipflixServers.cdnUrl);

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
        route = SipflixConnectionManager.nextRoute(alpha, route);
        seen.add(route.id);
      }
      expect(seen, ['cdn1', 'cdn2', 'direct']);
      expect(SipflixConnectionManager.nextRoute(alpha, route).id, 'cdn1');
    });

    test("cycles a Delta record through Delta's own routes", () {
      final delta = recordOf(SipflixServers.delta, 'https://emby2.n2.d-crypt.io');
      final current = SipflixConnectionManager.currentRoute(delta);
      expect(current.id, 'direct');
      final next = SipflixConnectionManager.nextRoute(delta, current);
      expect(next.url, 'https://emby.cdn2.d-crypt.io');
      expect(SipflixConnectionManager.nextRoute(delta, next).id, 'direct');
    });
  });

  group('multiple servers', () {
    test('AlphaV2 keeps the record id every existing box already has', () {
      expect(SipflixServers.alphaV2.recordId,
          '51901ff1-a001-4000-8000-000000000001');
      expect(SipflixServers.alphaV2.recordId, SipflixServers.serverId);
    });

    test('shows real names, emby2 as Delta', () {
      expect(SipflixServers.all.map((d) => d.name),
          ['AlphaV2', 'Delta', 'iDuck', 'Sipflix DUMB']);
      expect(SipflixServers.delta.key, 'emby2');
    });

    test('record ids and route URLs are unique across servers', () {
      final ids = SipflixServers.all.map((d) => d.recordId).toSet();
      expect(ids.length, SipflixServers.all.length);
      final urls = [
        for (final d in SipflixServers.all)
          for (final r in d.routes) r.url,
      ];
      expect(urls.toSet().length, urls.length);
    });

    test('recognises Delta and iDuck addresses, not only AlphaV2', () {
      for (final d in SipflixServers.all) {
        expect(SipflixServers.isSipflixServerRef(d.recordId), isTrue);
        for (final r in d.routes) {
          expect(SipflixServers.defForRef(r.url)?.key, d.key);
          expect(SipflixServers.defForRef('${r.url}/')?.key, d.key);
        }
      }
    });

    test('a record is identified by id, or by address for a foreign id', () {
      final byId = recordOf(SipflixServers.iDuck, 'https://x.example');
      expect(SipflixServers.defForServer(byId)?.key, 'iDuck');
      final foreign = Server(
        id: 'something-else',
        name: 'Old',
        address: 'https://emby2.n2.d-crypt.io',
        version: '4.9.5.0',
        serverType: ServerType.emby,
        setupCompleted: true,
        dateAdded: DateTime(2026),
      );
      expect(SipflixServers.defForServer(foreign)?.key, 'emby2');
      expect(SipflixServers.routesFor(foreign), SipflixServers.delta.routes);
    });

    test('findServer prefers the active record when a box holds two', () {
      final a = recordOf(SipflixServers.alphaV2, SipflixServers.cdnUrl);
      final d = recordOf(SipflixServers.delta, 'https://emby2.n2.d-crypt.io');
      expect(SipflixServers.findServer([a, d])?.id, a.id);
      expect(SipflixServers.findServer([a, d], preferId: d.id)?.id, d.id);
    });
  });
}
