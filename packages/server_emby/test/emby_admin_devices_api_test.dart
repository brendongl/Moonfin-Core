import 'package:server_core/server_core.dart';
import 'package:server_emby/src/api/emby_admin_devices_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  final devices = {
    'Items': [
      {
        'Id': '2',
        'Name': 'probe',
        'ReportedDeviceId': 'api-a-probe',
        'LastUserId': 'u1',
        'DateLastActivity': '2026-10-17T14:53:18.0000000Z',
      },
      {'Id': '1', 'Name': 'harness', 'LastUserId': 'u2'},
    ],
    'TotalRecordCount': 0,
  };

  test('devices keep the internal and the reported id', () async {
    final fake = AdminFake({'/Devices': devices});
    final list = await EmbyAdminDevicesApi(fake.dio).getDevices();

    expect(list.first.id, '2');
    expect(list.first.reportedDeviceId, 'api-a-probe');
    expect(list.first.dateLastActivity, isNotNull);
  });

  test('a user filter is matched against the last user', () async {
    final fake = AdminFake({'/Devices': devices});
    final list = await EmbyAdminDevicesApi(fake.dio).getDevices(userId: 'u2');

    expect(fake.last.queryParameters, isEmpty);
    expect(list.single.id, '1');
  });

  test('options, info and delete take Id', () async {
    final fake = AdminFake();
    final api = EmbyAdminDevicesApi(fake.dio);

    await api.getDeviceInfo('2');
    await api.getDeviceOptions('2');
    await api.updateDeviceOptions(
      '2',
      const DeviceOptionsDto(customName: 'Living room'),
    );
    await api.deleteDevice('2');

    expect(
      [
        for (final r in fake.requests)
          '${r.method} ${r.path} ${r.queryParameters}',
      ],
      [
        'GET /Devices/Info {Id: 2}',
        'GET /Devices/Options {Id: 2}',
        'POST /Devices/Options {Id: 2}',
        'DELETE /Devices {Id: 2}',
      ],
    );
    expect(fake.requests[2].data, {'CustomName': 'Living room'});
  });
}
