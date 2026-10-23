import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/login_state.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/auth_repository.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/sipflix/sipflix_account_probe.dart';
import 'package:moonfin/sipflix/sipflix_credential_vault.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:moonfin/sipflix/sipflix_sign_in.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Servers extends Fake implements ServerRepository {
  _Servers(this.store);
  final AuthenticationStore store;
  @override
  List<Server> get servers => store.getServers();
  @override
  Future<void> loadStoredServers() async {}
  @override
  Future<void> deleteServer(String serverId) async =>
      fail('Switch must not delete a server');
}

class _Sessions extends Fake implements SessionRepository {
  @override
  String? activeServerId;
  final calls =
      <
        ({
          String serverId,
          String userId,
          String? username,
          String? password,
          bool validate,
        })
      >[];
  bool succeed = true;
  @override
  Future<bool> switchCurrentSession({
    required String serverId,
    required String userId,
    String? username,
    String? password,
    bool validateToken = false,
  }) async {
    calls.add((
      serverId: serverId,
      userId: userId,
      username: username,
      password: password,
      validate: validateToken,
    ));
    if (succeed) activeServerId = serverId;
    return succeed;
  }

  @override
  Future<void> destroyCurrentSession({bool tokenKnownInvalid = false}) async =>
      fail('Switch must not sign out existing accounts');
}

class _Client extends Fake implements MediaServerClient {
  @override
  String baseUrl = '';
}

class _Factory extends Fake implements MediaServerClientFactory {
  @override
  MediaServerClient getClient({
    required String serverId,
    required ServerType serverType,
    required String baseUrl,
  }) => _Client()..baseUrl = baseUrl;
}

class _Auth extends Fake implements AuthRepository {
  _Auth(this.store);
  final AuthenticationStore store;
  final activations = <bool>[];
  @override
  Future<LoginState> adoptAuthResult({
    required Map<String, dynamic> result,
    required MediaServerClient client,
    required String serverId,
    required String fallbackName,
    bool activate = true,
  }) async {
    activations.add(activate);
    final user = result['User'] as Map<String, dynamic>;
    await store.putUser(
      PrivateUser(
        id: user['Id'] as String,
        name: fallbackName,
        serverId: serverId,
        accessToken: result['AccessToken'] as String,
        lastUsed: DateTime.utc(2026),
      ),
    );
    return Authenticated(userId: user['Id'] as String, serverId: serverId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthenticationStore store;
  late SipflixCredentialVault vault;
  late _Sessions sessions;
  late _Auth auth;
  late SipflixSignIn flow;
  late int probes;
  late int logouts;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    store = AuthenticationStore();
    await store.init();
    vault = SipflixCredentialVault();
    sessions = _Sessions();
    auth = _Auth(store);
    probes = 0;
    logouts = 0;
    flow = SipflixSignIn(
      probe: SipflixAccountProbe(
        auth: (_, _, _) async {
          probes++;
          return (status: 401, body: null);
        },
        logout: (_, _) async {
          logouts++;
        },
      ),
      serverRepo: _Servers(store),
      authStore: store,
      authRepo: auth,
      sessionRepo: sessions,
      clientFactory: _Factory(),
      vault: vault,
    );
  });
  SipflixProbeResult accepted(SipflixServerDef server, String id) =>
      SipflixProbeResult(
        server: server,
        outcome: SipflixProbeOutcome.accepted,
        routeUrl: server.defaultRoute.url,
        authResult: {
          'User': {'Id': id},
          'AccessToken': 'test-token-$id',
        },
      );

  test('different credentials saved on Alpha and Silo survive switching both directions', () async {
    final alpha = SipflixServers.alphaV2;
    final silo = SipflixServers.all.singleWhere(
      (s) => s.serverType == ServerType.jellyfin,
    );
    expect(
      await flow.connect(
        accepted(alpha, 'alpha-user'),
        username: 'alpha-name',
        password: 'alpha-password',
      ),
      isTrue,
    );
    expect(
      await flow.connect(
        accepted(silo, 'silo-user'),
        username: 'silo-name',
        password: 'silo-password',
      ),
      isTrue,
    );
    expect(flow.savedAccounts, hasLength(2));
    final alphaAccount = flow.savedAccounts.singleWhere(
      (a) => a.server.id == alpha.recordId,
    );
    expect(await flow.connectSaved(alphaAccount), isTrue);
    expect(sessions.calls.last.validate, isTrue);
    expect(sessions.calls.last.password, 'alpha-password');
    expect((await vault.read())?.username, 'alpha-name');
    final siloAccount = flow.savedAccounts.singleWhere(
      (a) => a.server.id == silo.recordId,
    );
    expect(await flow.connectSaved(siloAccount), isTrue);
    expect(sessions.calls.last.password, 'silo-password');
    expect(
      store.getUsers(alpha.recordId).single.accessToken,
      'test-token-alpha-user',
    );
    expect(
      store.getUsers(silo.recordId).single.accessToken,
      'test-token-silo-user',
    );
    expect(probes, 0);
    expect(logouts, 0);
  });
  test('remembering secondary accepted account does not activate it', () async {
    final alpha = SipflixServers.alphaV2;
    final silo = SipflixServers.all.singleWhere(
      (s) => s.serverType == ServerType.jellyfin,
    );
    await flow.connect(accepted(alpha, 'a'), username: 'alpha', password: 'a');
    await flow.remember(accepted(silo, 's'), username: 'silo', password: 's');
    expect(auth.activations, [true, false]);
    expect(sessions.calls, hasLength(1));
    expect((await vault.read())?.username, 'alpha');
    expect((await vault.read(serverId: silo.recordId))?.username, 'silo');
  });
  test('saved token without password is still offered and validated', () async {
    final server = SipflixServers.alphaV2.toRecord();
    await store.putServer(server);
    await store.putUser(
      PrivateUser(
        id: 'token-only',
        name: 'Token user',
        serverId: server.id,
        accessToken: 'test-saved-token',
        lastUsed: DateTime.utc(2026),
      ),
    );
    expect(await flow.connectSaved(flow.savedAccounts.single), isTrue);
    expect(sessions.calls.single.validate, isTrue);
    expect(sessions.calls.single.password, isNull);
    expect(probes, 0);
  });
  test(
    'failed saved switch preserves current vault account and other records',
    () async {
      final alpha = SipflixServers.alphaV2;
      final silo = SipflixServers.all.singleWhere(
        (s) => s.serverType == ServerType.jellyfin,
      );
      await flow.connect(
        accepted(alpha, 'a'),
        username: 'alpha',
        password: 'a',
      );
      await flow.remember(accepted(silo, 's'), username: 'silo', password: 's');
      sessions.succeed = false;
      expect(
        await flow.connectSaved(
          flow.savedAccounts.singleWhere((a) => a.server.id == silo.recordId),
        ),
        isFalse,
      );
      expect((await vault.read())?.username, 'alpha');
      expect(flow.savedAccounts, hasLength(2));
    },
  );
  test('adding Silo preserves legacy active Alpha credentials', () async {
    final alpha = SipflixServers.alphaV2;
    final silo = SipflixServers.all.singleWhere(
      (s) => s.serverType == ServerType.jellyfin,
    );
    sessions.activeServerId = alpha.recordId;
    await vault.save('legacy-alpha', 'legacy-password');
    await flow.connect(accepted(silo, 's'), username: 'silo', password: 's');
    expect(
      (await vault.read(serverId: alpha.recordId))?.username,
      'legacy-alpha',
    );
    expect((await vault.read(serverId: silo.recordId))?.username, 'silo');
  });
}
