// Regression tests for the "Switch User -> Select Server wipes auth store"
// bug (swarm-20261004, finding R1-A issue 1): loadStoredServers() deduped
// servers that resolve to the same endpoint identity by always keeping
// whichever record happened to be first in storage order and deleting the
// rest, with no regard for which record actually had signed-in users. If
// the kept record was the empty one, the account with users was deleted
// permanently with no recovery (the symptom observed live: Shield's
// AlphaV2 admin token vanished from authentication_store_json, leaving
// servers:{}).
//
// The fix groups stored records by endpoint identity, prefers a record
// that has users over one that doesn't, and never deletes a record that
// has users unless another member of the same group is kept in its place
// (in which case both are kept rather than destroying either).
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';

class _MockClientFactory extends Mock implements MediaServerClientFactory {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthenticationStore authStore;
  late ServerRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authStore = AuthenticationStore();
    await authStore.init();
    repo = ServerRepository(authStore, _MockClientFactory());
  });

  Server _server(String id, String address, {DateTime? dateAdded}) => Server(
        id: id,
        name: 'AlphaV2',
        address: address,
        version: '4.9.5.0',
        serverType: ServerType.emby,
        dateAdded: dateAdded ?? DateTime(2026, 1, 1),
      );

  PrivateUser _user(String id, String serverId) => PrivateUser(
        id: id,
        name: 'admin',
        serverId: serverId,
        accessToken: 'token-$id',
        lastUsed: DateTime(2026, 1, 1),
        isAdministrator: true,
      );

  test(
    'dedupe keeps the duplicate that has users, even when it is not first in storage',
    () async {
      // Same endpoint, two different stored ids: "server-a" was stored
      // first (as the old code's dedupe happened to pick), but only
      // "server-b" actually has a signed-in user.
      await authStore.putServer(
        _server('server-a', 'https://emby.n2.d-crypt.io'),
      );
      await authStore.putServer(
        _server('server-b', 'https://emby.n2.d-crypt.io'),
      );
      await authStore.putUser(_user('admin-1', 'server-b'));

      await repo.loadStoredServers();

      expect(repo.servers, hasLength(1));
      expect(repo.servers.single.id, 'server-b');
      expect(authStore.getUsers('server-b'), hasLength(1));
      // The loser must be gone from storage (not just from the in-memory
      // list) since it never had an account on it.
      expect(authStore.getServer('server-a'), isNull);
    },
  );

  test(
    'dedupe never deletes a server that has users, even if another duplicate also has users',
    () async {
      await authStore.putServer(
        _server('server-a', 'https://emby.n2.d-crypt.io'),
      );
      await authStore.putServer(
        _server('server-b', 'https://emby.n2.d-crypt.io'),
      );
      await authStore.putUser(_user('admin-1', 'server-a'));
      await authStore.putUser(_user('admin-2', 'server-b'));

      await repo.loadStoredServers();

      // Both accounts must survive: neither is silently deleted just
      // because they collide on endpoint identity.
      final ids = repo.servers.map((s) => s.id).toSet();
      expect(ids, {'server-a', 'server-b'});
      expect(authStore.getServer('server-a'), isNotNull);
      expect(authStore.getServer('server-b'), isNotNull);
    },
  );

  test(
    'non-colliding servers with users are all preserved (no wipe to empty)',
    () async {
      await authStore.putServer(_server('alpha', 'https://emby.n2.d-crypt.io'));
      await authStore.putServer(
        _server('delta', 'https://emby2.n2.d-crypt.io'),
      );
      await authStore.putUser(_user('admin-1', 'alpha'));
      await authStore.putUser(_user('gan', 'delta'));

      await repo.loadStoredServers();

      expect(repo.servers, hasLength(2));
      expect(authStore.getUsers('alpha'), hasLength(1));
      expect(authStore.getUsers('delta'), hasLength(1));
    },
  );

  test(
    'dedupe without any users keeps exactly one survivor, not zero',
    () async {
      await authStore.putServer(
        _server('server-a', 'https://emby.n2.d-crypt.io'),
      );
      await authStore.putServer(
        _server('server-b', 'https://emby.n2.d-crypt.io'),
      );

      await repo.loadStoredServers();

      expect(repo.servers, hasLength(1));
    },
  );
}
