import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_bandwidth_probe.dart';
import 'package:moonfin/sipflix/sipflix_route_selector.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

const first = SipflixRouteDef(
  id: 'one',
  label: 'One',
  url: 'https://one.invalid',
);
const second = SipflixRouteDef(
  id: 'two',
  label: 'Two',
  url: 'https://two.invalid',
);
const third = SipflixRouteDef(
  id: 'three',
  label: 'Three',
  url: 'https://three.invalid',
);

void main() {
  late Object client;
  late SipflixRouteSession? session;
  late bool busy;
  late DateTime now;
  late List<String> probes;
  late List<String> applied;
  late Map<String, double> speeds;
  late SipflixRouteSelector selector;
  SipflixRouteSession snapshot({
    String address = 'https://one.invalid',
    String user = 'tester',
    String token = 'test-token',
    List<SipflixRouteDef> routes = const [first, second, third],
  }) => SipflixRouteSession(
    serverId: 'test-server',
    userId: user,
    token: token,
    address: address,
    clientIdentity: client,
    routes: routes,
  );

  SipflixRouteSelector make({SipflixRouteProbe? probe, Duration? timeout}) =>
      SipflixRouteSelector(
        currentSession: () => session,
        playbackBusy: () => busy,
        now: () => now,
        routeTimeout: timeout ?? const Duration(seconds: 1),
        probe:
            probe ??
            (route, token, cancelled) async {
              probes.add(route.id);
              final speed = speeds[route.id];
              return speed == null
                  ? null
                  : SipflixRouteMeasurement(
                      burstMbps: 1000 - speed,
                      sustainedMbps: speed,
                    );
            },
        apply: (old, route, current) async {
          if (!current()) return false;
          applied.add(route.id);
          session = snapshot(address: route.url);
          return true;
        },
      );

  setUp(() {
    client = Object();
    session = snapshot();
    busy = false;
    now = DateTime.utc(2026, 10, 23);
    probes = [];
    applied = [];
    speeds = {'one': 5, 'two': 30, 'three': 10};
    selector = make();
  });

  test('chooses sustained speed over burst and checks every route', () async {
    expect(await selector.refreshIfStale(), second);
    expect(probes, ['one', 'two', 'three']);
    expect(applied, ['two']);
  });

  test(
    'successful route cached for four hours, rechecks after expiry',
    () async {
      await selector.refreshIfStale();
      now = now.add(const Duration(hours: 3));
      expect(await selector.refreshIfStale(), isNull);
      expect(probes, hasLength(3));
      now = now.add(const Duration(hours: 1));
      expect(await selector.refreshIfStale(), second);
      expect(probes, hasLength(6));
      expect(applied, ['two']);
    },
  );

  test('bitrate reservation prevents competing route downloads', () async {
    expect(selector.beginBandwidthMeasurement(), isTrue);
    expect(selector.beginBandwidthMeasurement(), isFalse);
    expect(await selector.refreshIfStale(force: true), isNull);
    expect(probes, isEmpty);
    selector.endBandwidthMeasurement();
    expect(await selector.refreshIfStale(), second);
  });

  test('single route never invokes Emby probe', () async {
    session = snapshot(routes: [first]);
    expect(await selector.refreshIfStale(force: true), isNull);
    expect(probes, isEmpty);
  });

  test('missing session does nothing', () async {
    session = null;
    expect(await selector.refreshIfStale(), isNull);
    expect(probes, isEmpty);
  });

  test('active or paused queued playback prevents all probes', () async {
    busy = true;
    expect(await selector.refreshIfStale(force: true), isNull);
    expect(probes, isEmpty);
    expect(applied, isEmpty);
  });

  test('playback beginning during probe cancels before any apply', () async {
    final gate = Completer<SipflixRouteMeasurement?>();
    late bool Function() cancelled;
    selector = make(
      probe: (route, token, cancel) {
        cancelled = cancel;
        return gate.future;
      },
    );
    final result = selector.refreshIfStale();
    busy = true;
    expect(cancelled(), isTrue);
    gate.complete(
      const SipflixRouteMeasurement(burstMbps: 10, sustainedMbps: 8),
    );
    expect(await result, isNull);
    expect(applied, isEmpty);
  });

  for (final change in ['user', 'token', 'client', 'address', 'logout']) {
    test('stale $change cannot apply previous session measurements', () async {
      final gate = Completer<SipflixRouteMeasurement?>();
      selector = make(probe: (_, _, _) => gate.future);
      final result = selector.refreshIfStale();
      switch (change) {
        case 'user':
          session = snapshot(user: 'different');
        case 'token':
          session = snapshot(token: 'replacement');
        case 'client':
          client = Object();
          session = snapshot();
        case 'address':
          session = snapshot(address: third.url);
        case 'logout':
          session = null;
      }
      gate.complete(
        const SipflixRouteMeasurement(burstMbps: 20, sustainedMbps: 15),
      );
      expect(await result, isNull);
      expect(applied, isEmpty);
    });
  }

  test(
    'background cancellation suppresses apply even after foreground returns',
    () async {
      final gate = Completer<SipflixRouteMeasurement?>();
      selector = make(probe: (_, _, _) => gate.future);
      final result = selector.refreshIfStale();
      selector.cancel();
      gate.complete(
        const SipflixRouteMeasurement(burstMbps: 20, sustainedMbps: 15),
      );
      expect(await result, isNull);
      expect(applied, isEmpty);
    },
  );

  test('concurrent invocation does not start a second probe set', () async {
    final gate = Completer<SipflixRouteMeasurement?>();
    var calls = 0;
    selector = make(
      probe: (_, _, _) {
        calls++;
        return gate.future;
      },
    );
    final result = selector.refreshIfStale();
    expect(await selector.refreshIfStale(force: true), isNull);
    expect(calls, 1);
    selector.cancel();
    gate.complete(null);
    await result;
  });

  test('failure preserves route and cools down, then retries', () async {
    speeds.clear();
    expect(await selector.refreshIfStale(), isNull);
    expect(applied, isEmpty);
    now = now.add(const Duration(minutes: 14));
    await selector.refreshIfStale();
    expect(probes, hasLength(3));
    now = now.add(const Duration(minutes: 1));
    await selector.refreshIfStale();
    expect(probes, hasLength(6));
  });

  test('tie keeps current route', () async {
    speeds = {'one': 10, 'two': 10, 'three': 10};
    expect(await selector.refreshIfStale(), first);
    expect(applied, isEmpty);
  });

  test('nonfinite and negative speed cannot win', () async {
    speeds = {'one': double.nan, 'two': double.infinity, 'three': -5};
    expect(await selector.refreshIfStale(), isNull);
    expect(applied, isEmpty);
  });

  test('throwing route still allows remaining routes', () async {
    selector = make(
      probe: (route, _, _) async {
        probes.add(route.id);
        if (route == first) throw StateError('unreachable');
        return SipflixRouteMeasurement(
          burstMbps: 100,
          sustainedMbps: route == second ? 20 : 5,
        );
      },
    );
    expect(await selector.refreshIfStale(), second);
    expect(probes, hasLength(3));
  });

  test('timed out route gets cancellation and remaining route wins', () async {
    late bool Function() cancelFirst;
    selector = make(
      timeout: const Duration(milliseconds: 10),
      probe: (route, _, cancel) async {
        if (route == first) {
          cancelFirst = cancel;
          return Completer<SipflixRouteMeasurement?>().future;
        }
        return SipflixRouteMeasurement(
          burstMbps: 100,
          sustainedMbps: route == second ? 20 : 5,
        );
      },
    );
    expect(await selector.refreshIfStale(), second);
    expect(cancelFirst(), isTrue);
  });
}
