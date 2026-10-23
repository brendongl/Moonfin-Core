import 'package:server_emby/src/api/emby_admin_users_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  test('users are listed from the query', () async {
    final fake = AdminFake({
      '/Users/Query': {
        'Items': [
          {'Id': 'u1', 'Name': 'claude'},
        ],
        'TotalRecordCount': 1,
      },
    });
    final users = await EmbyAdminUsersApi(fake.dio).getUsers(isDisabled: false);

    expect(fake.last.queryParameters, {'IsDisabled': false});
    expect(users.single.id, 'u1');
  });

  test('a new user gets the password set after it is created', () async {
    final fake = AdminFake({
      '/Users/New': {'Id': 'u2', 'Name': 'new', 'HasPassword': false},
      '/Users/u2': {'Id': 'u2', 'Name': 'new', 'HasPassword': true},
    });
    final user = await EmbyAdminUsersApi(fake.dio).createUser('new', 'pw');

    expect(
      [for (final r in fake.requests) '${r.method} ${r.path}'],
      ['POST /Users/New', 'POST /Users/u2/Password', 'GET /Users/u2'],
    );
    expect(fake.requests[0].data, {'Name': 'new'});
    expect(fake.requests[1].data, {'NewPw': 'pw', 'ResetPassword': false});
    expect(user.hasPassword, isTrue);
  });

  test('a new user without a password is one request', () async {
    final fake = AdminFake({
      '/Users/New': {'Id': 'u3', 'Name': 'open'},
    });
    final user = await EmbyAdminUsersApi(fake.dio).createUser('open', null);

    expect(fake.requests, hasLength(1));
    expect(user.id, 'u3');
  });

  test('user, policy, password and delete go to the user id', () async {
    final fake = AdminFake();
    final api = EmbyAdminUsersApi(fake.dio);

    await api.updateUser('u1', {'Name': 'x'});
    await api.updateUserPolicy('u1', {'IsAdministrator': false});
    await api.updateUserPassword('u1', resetPassword: true);
    await api.deleteUser('u1');

    expect(
      [for (final r in fake.requests) '${r.method} ${r.path}'],
      [
        'POST /Users/u1',
        'POST /Users/u1/Policy',
        'POST /Users/u1/Password',
        'DELETE /Users/u1',
      ],
    );
    expect(fake.requests[2].data, {'ResetPassword': true});
  });

  test('channels pass the deletion filter', () async {
    final fake = AdminFake({
      '/Channels': {
        'Items': [
          {'Id': 'c1'},
        ],
      },
    });
    final channels = await EmbyAdminUsersApi(
      fake.dio,
    ).getChannels(supportsMediaDeletion: true);

    expect(fake.last.queryParameters, {'SupportsMediaDeletion': true});
    expect(channels.single['Id'], 'c1');
  });
}
