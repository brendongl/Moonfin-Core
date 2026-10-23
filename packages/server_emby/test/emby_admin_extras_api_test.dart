import 'package:server_emby/src/api/emby_admin_extras_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  late AdminFake fake;
  late EmbyAdminExtrasApi api;

  setUp(() {
    fake = AdminFake();
    api = EmbyAdminExtrasApi(fake.dio);
  });

  group('Premiere', () {
    test('no key at all', () async {
      fake.responses['/Plugins/SecurityInfo'] = {'IsMBSupporter': false};

      final status = await api.getPremiereStatus();

      expect(status.hasKey, isFalse);
      expect(status.isKeyInvalid, isFalse);
      expect(await api.getPremiereKey(), isNull);
    });

    test('a removed key comes back empty and counts as none', () async {
      fake.responses['/Plugins/SecurityInfo'] = {
        'IsMBSupporter': false,
        'SupporterKey': '',
      };

      expect((await api.getPremiereStatus()).hasKey, isFalse);
      expect(await api.getPremiereKey(), isNull);
    });

    test('a key that unlocks nothing is invalid', () async {
      fake.responses['/Plugins/SecurityInfo'] = {
        'IsMBSupporter': false,
        'SupporterKey': 'k',
      };

      expect((await api.getPremiereStatus()).isKeyInvalid, isTrue);
      expect(await api.getPremiereKey(), 'k');
    });

    test('an active key', () async {
      fake.responses['/Plugins/SecurityInfo'] = {
        'IsMBSupporter': true,
        'SupporterKey': 'k',
      };

      final status = await api.getPremiereStatus();

      expect(status.isActive, isTrue);
      expect(status.isKeyInvalid, isFalse);
    });

    test('saving posts the key', () async {
      await api.setPremiereKey('');

      expect(fake.last.method, 'POST');
      expect(fake.last.data, {'SupporterKey': ''});
    });
  });

  test('sync jobs split conversions from downloads', () async {
    fake.responses['/Sync/Jobs'] = {
      'Items': [
        {'Id': 1},
      ],
      'TotalRecordCount': 1,
    };

    expect((await api.getSyncJobs(conversions: true)).single['Id'], 1);
    expect(fake.last.queryParameters, {
      'IncludeProviders': 'ConvertSyncProvider',
    });

    await api.getSyncJobs(conversions: false);
    expect(fake.last.queryParameters, {
      'ExcludeProviders': 'ConvertSyncProvider',
    });

    await api.cancelSyncJob('1');
    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/Sync/Jobs/1/Delete');
  });

  test('managed channels page in the channel order', () async {
    await api.getManagedChannels(startIndex: 100, limit: 50);
    expect(fake.last.queryParameters, {
      'StartIndex': 100,
      'Limit': 50,
      'SortBy': 'DefaultChannelOrder',
      'SortOrder': 'Ascending',
    });

    await api.setChannelDisabled('c1', managementId: 'm1', disabled: true);
    expect(fake.last.path, '/LiveTv/Manage/Channels/c1/Disabled');
    expect(fake.last.queryParameters, {'ManagementId': 'm1', 'Disabled': true});

    await api.setChannelSortIndex('c1', managementId: 'm1', newIndex: 3);
    expect(fake.last.path, '/LiveTv/Manage/Channels/c1/SortIndex');
    expect(fake.last.queryParameters, {'ManagementId': 'm1', 'NewIndex': 3});
  });

  test('guide sources filter by country only when given one', () async {
    await api.getAvailableListingProviders();
    expect(fake.last.queryParameters, isEmpty);

    await api.getAvailableListingProviders(country: 'DEU');
    expect(fake.last.path, '/LiveTv/ListingProviders/Available');
    expect(fake.last.queryParameters, {'Country': 'DEU'});
  });

  test('Emby Connect link and unlink', () async {
    fake.responses['/Users/u1/Connect/Link'] = {'IsPending': true};

    final result = await api.linkConnectUser('u1', 'someone');

    expect(result['IsPending'], isTrue);
    expect(fake.last.method, 'POST');
    expect(fake.last.queryParameters, {'ConnectUsername': 'someone'});

    await api.unlinkConnectUser('u1');
    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/Users/u1/Connect/Link/Delete');
  });

  test("a restore sends the plugin's request shape", () async {
    await api.restoreBackup();
    expect(fake.last.path, '/BackupRestore/Restore');
    expect(fake.last.data, {'RestoreServerId': false, 'UseFiles': null});

    await api.restoreBackup(restoreServerId: true, lightBackupName: 'light');
    expect(fake.last.data, {'RestoreServerId': true, 'UseFiles': 'light'});
  });
}
