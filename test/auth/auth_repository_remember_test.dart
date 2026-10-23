import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/login_state.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/auth_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/auth/store/authentication_preferences.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:server_core/server_core.dart';

// All state is in memory. These fakes deliberately fail if remembering a
// secondary account attempts to mutate the current user or login preferences.
class _Store extends Fake implements AuthenticationStore {
  final users = <PrivateUser>[];
  @override
  Future<void> putUser(PrivateUser user) async => users.add(user);
}

class _Prefs extends Fake implements AuthenticationPreferences {}

class _Sessions extends Fake implements SessionRepository {}

class _Users extends Fake implements UserRepository {}

class _Client extends Fake implements MediaServerClient {
  @override
  String? accessToken;
  @override
  String? userId;
}

void main() {
  test(
    'remembering a secondary login stores it without activating it',
    () async {
      final store = _Store();
      final repo = AuthRepository(store, _Prefs(), _Sessions(), _Users());
      final events = <LoginState>[];
      final subscription = repo.stateStream.listen(events.add);
      final client = _Client()
        ..accessToken = 'playing-token'
        ..userId = 'playing-user';
      final result = await repo.adoptAuthResult(
        result: {
          'AccessToken': 'test-token',
          'User': {'Id': 'silo-user', 'Name': 'test'},
        },
        client: client,
        serverId: 'silo',
        fallbackName: 'test',
        activate: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(result, isA<Authenticated>());
      expect(store.users.single.serverId, 'silo');
      expect(events, isEmpty);
      expect(client.accessToken, 'playing-token');
      expect(client.userId, 'playing-user');
      await subscription.cancel();
    },
  );
}
