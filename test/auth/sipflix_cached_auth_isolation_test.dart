import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/auth/models/login_state.dart';
import 'package:moonfin/auth/repositories/auth_repository.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/auth/store/authentication_preferences.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/sipflix/sipflix_account_probe.dart';
import 'package:moonfin/sipflix/sipflix_credential_vault.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:moonfin/sipflix/sipflix_sign_in.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Prefs extends Fake implements AuthenticationPreferences {}

class _Users extends Fake implements UserRepository {}

class _Sessions extends Fake implements SessionRepository {
  _Sessions(this.beforeSwitch);
  final void Function() beforeSwitch;
  int calls = 0;
  @override
  String? get activeServerId => SipflixServers.alphaV2.recordId;
  @override
  Future<bool> switchCurrentSession({
    required String serverId,
    required String userId,
    String? username,
    String? password,
    bool validateToken = false,
  }) async {
    beforeSwitch();
    calls++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final connect in [false, true]) {
    test(
      '${connect ? "connect" : "remember"} stores probe auth without mutating real cached client before switch',
      () async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        await GetIt.instance.reset();
        final def = SipflixServers.alphaV2;
        final oldRoute = def.defaultRoute.url;
        final newRoute = def.routes.last.url;
        final store = AuthenticationStore();
        await store.init();
        await store.putServer(def.toRecord());
        final factory = MediaServerClientFactory(
          deviceInfo: const DeviceInfo(
            id: 'unit-test',
            name: 'Unit Test',
            appName: 'Moonfin Test',
            appVersion: 'test',
          ),
        );
        final cached = factory.getClient(
          serverId: def.recordId,
          serverType: def.serverType,
          baseUrl: oldRoute,
        );
        cached.accessToken = 'playing-token';
        cached.userId = 'playing-user';
        // This proves the real factory does not recreate or retarget a cache hit.
        expect(
          factory.getClient(
            serverId: def.recordId,
            serverType: def.serverType,
            baseUrl: newRoute,
          ),
          same(cached),
        );
        expect(cached.baseUrl, oldRoute);
        void assertUnchanged() {
          expect(cached.baseUrl, oldRoute);
          expect(cached.accessToken, 'playing-token');
          expect(cached.userId, 'playing-user');
        }

        final sessions = _Sessions(assertUnchanged);
        final auth = AuthRepository(store, _Prefs(), sessions, _Users());
        final events = <LoginState>[];
        final subscription = auth.stateStream.listen(events.add);
        final flow = SipflixSignIn(
          probe: SipflixAccountProbe(
            auth: (_, _, _) async => throw StateError('no network'),
            logout: (_, _) async => throw StateError('no logout'),
          ),
          serverRepo: ServerRepository(store, factory),
          authStore: store,
          authRepo: auth,
          sessionRepo: sessions,
          vault: SipflixCredentialVault(),
        );
        final accepted = SipflixProbeResult(
          server: def,
          outcome: SipflixProbeOutcome.accepted,
          routeUrl: newRoute,
          authResult: {
            'AccessToken': 'new-token',
            'User': {'Id': 'new-user', 'Name': 'new-name'},
          },
        );
        final ok = connect
            ? await flow.connect(
                accepted,
                username: 'new-name',
                password: 'test-password',
              )
            : await flow.remember(
                accepted,
                username: 'new-name',
                password: 'test-password',
              );
        await pumpEventQueue();
        expect(ok, isTrue);
        assertUnchanged();
        expect(
          store.getUser(def.recordId, 'new-user')?.accessToken,
          'new-token',
        );
        expect(store.getServer(def.recordId)?.address, newRoute);
        expect(sessions.calls, connect ? 1 : 0);
        expect(events, isEmpty);
        await subscription.cancel();
        auth.dispose();
        cached.dispose();
      },
    );
  }
}
