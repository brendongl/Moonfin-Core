import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/sipflix/sipflix_auto_bitrate_service.dart';
import 'package:moonfin/sipflix/sipflix_bandwidth_probe.dart';
import 'package:moonfin/sipflix/sipflix_connection_manager.dart';
import 'package:moonfin/sipflix/sipflix_route_selector.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Fake implements MediaServerClient {
  @override
  String baseUrl = SipflixServers.alphaV2.defaultRoute.url;
  @override
  String? accessToken = 'test-token';
  @override
  ServerType serverType = ServerType.emby;
}

class _Factory extends Fake implements MediaServerClientFactory {
  _Factory(this.client);
  final _Client client;
  @override
  MediaServerClient getActiveClient() => client;
  @override
  MediaServerClient? getClientIfExists(String serverId) => client;
}

class _Repo extends Fake implements ServerRepository {
  final writes = <Server>[];
  Completer<void>? gate;
  @override
  Future<void> updateServer(Server server) async {
    writes.add(server);
    await gate?.future;
  }
}

class _Probe extends SipflixBandwidthProbe {
  int calls = 0;
  Completer<double?>? gate;
  @override
  Future<double?> measureMbps({
    required String baseUrl,
    required String? accessToken,
  }) async {
    calls++;
    return gate == null ? 25 : gate!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Client client;
  late _Factory factory;
  late UserPreferences prefs;
  late _Probe probe;
  late SipflixAutoBitrateService auto;
  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    client = _Client();
    factory = _Factory(client);
    probe = _Probe();
    auto = SipflixAutoBitrateService(
      prefs: prefs,
      clientFactory: factory,
      probe: probe,
    );
    GetIt.instance.registerSingleton<MediaServerClient>(client);
  });
  tearDown(() => GetIt.instance.reset());

  test(
    'automatic route check rejects stale owner without persistence or mutation',
    () async {
      final repo = _Repo();
      final server = SipflixServers.alphaV2.toRecord();
      final picked = SipflixServers.alphaV2.routes.last;
      expect(
        await SipflixConnectionManager.applyAutomaticRoute(
          server,
          picked,
          repo,
          factory,
          stillCurrent: () => false,
        ),
        isFalse,
      );
      expect(repo.writes, isEmpty);
      expect(client.baseUrl, server.address);
    },
  );

  test(
    'retarget happens synchronously before asynchronous disk write',
    () async {
      final repo = _Repo()..gate = Completer<void>();
      final server = SipflixServers.alphaV2.toRecord();
      final picked = SipflixServers.alphaV2.routes.last;
      var allowed = true;
      final result = SipflixConnectionManager.applyAutomaticRoute(
        server,
        picked,
        repo,
        factory,
        stillCurrent: () => allowed,
      );
      expect(client.baseUrl, picked.url);
      allowed = false; // Playback may begin while persistence is still pending.
      repo.gate!.complete();
      expect(await result, isTrue);
      expect(client.baseUrl, picked.url);
      expect(repo.writes.single.address, picked.url);
    },
  );

  test('non-Emby DUMB is not sent an Emby bitrate request', () async {
    client.serverType = ServerType.jellyfin;
    client.baseUrl = 'https://s.sipflix.net';
    expect(await auto.refreshIfStale(force: true), isNull);
    expect(probe.calls, 0);
  });

  test(
    'manual bitrate cap remains unchanged and normal refresh skips probe',
    () async {
      await prefs.set(UserPreferences.maxBitrate, '20');
      expect(await auto.refreshIfStale(), isNull);
      expect(probe.calls, 0);
      expect(await auto.refreshIfStale(force: true), 25);
      expect(prefs.get(UserPreferences.maxBitrate), '20');
    },
  );

  test('stale route result is not stored', () async {
    probe.gate = Completer<double?>();
    final result = auto.refreshIfStale(force: true);
    await pumpEventQueue();
    client.baseUrl = SipflixServers.alphaV2.routes.last.url;
    probe.gate!.complete(50);
    expect(await result, isNull);
    expect(prefs.get(UserPreferences.measuredBandwidthAt), 0);
  });

  test('stale token result is not stored', () async {
    probe.gate = Completer<double?>();
    final result = auto.refreshIfStale(force: true);
    await pumpEventQueue();
    client.accessToken = 'replacement';
    probe.gate!.complete(50);
    expect(await result, isNull);
    expect(prefs.get(UserPreferences.measuredBandwidthAt), 0);
  });

  test(
    'bitrate probe reserves link against home route refresh until completion',
    () async {
      final identity = Object();
      var routeCalls = 0;
      final selector = SipflixRouteSelector(
        currentSession: () => SipflixRouteSession(
          serverId: 'server',
          userId: 'user',
          token: 'test',
          address: client.baseUrl,
          clientIdentity: identity,
          routes: SipflixServers.alphaV2.routes,
        ),
        playbackBusy: () => false,
        probe: (_, _, _) async {
          routeCalls++;
          return null;
        },
        apply: (_, _, _) async => false,
      );
      GetIt.instance.registerSingleton<SipflixRouteSelector>(selector);
      probe.gate = Completer<double?>();
      final result = auto.refreshIfStale(force: true);
      await pumpEventQueue();
      final initial = routeCalls;
      expect(probe.calls, 1);
      expect(await selector.refreshIfStale(force: true), isNull);
      expect(routeCalls, initial);
      probe.gate!.complete(50);
      expect(await result, 50);
      await selector.refreshIfStale(force: true);
      expect(routeCalls, greaterThan(initial));
    },
  );
}
