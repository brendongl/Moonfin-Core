import 'package:server_emby/src/api/emby_admin_api_keys_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  test('keys are listed, created by app and revoked by token', () async {
    final fake = AdminFake({
      '/Auth/Keys': {
        'Items': [
          {'Id': 3, 'AccessToken': 'tok', 'AppName': 'app'},
        ],
        'TotalRecordCount': 0,
      },
    });
    final api = EmbyAdminApiKeysApi(fake.dio);

    final keys = await api.getApiKeys();
    expect((keys['Items'] as List).single['AccessToken'], 'tok');

    await api.createApiKey('moonfin');
    expect(fake.last.method, 'POST');
    expect(fake.last.queryParameters, {'App': 'moonfin'});

    await api.revokeApiKey('tok');
    expect(fake.last.method, 'DELETE');
    expect(fake.last.path, '/Auth/Keys/tok');
  });
}
