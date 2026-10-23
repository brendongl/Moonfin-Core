import 'package:server_emby/src/api/emby_admin_system_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  test('storage paths come from the system info', () async {
    final fake = AdminFake({
      '/System/Info': {
        'ProgramDataPath': '/config',
        'CachePath': '/config/cache',
        'LogPath': '/config/logs',
      },
    });
    final storage = await EmbyAdminSystemApi(fake.dio).getStorageInfo();

    expect(fake.last.path, '/System/Info');
    expect(storage.programDataPath, '/config');
    expect(storage.cachePath, '/config/cache');
    expect(storage.logPath, '/config/logs');
  });

  test('logs are listed from the query and read by name in the path', () async {
    final fake = AdminFake({
      '/System/Logs/Query': {
        'Items': [
          {
            'Name': 'embyserver.txt',
            'Size': 10,
            'DateCreated': '2026-10-17T14:52:45.0425985Z',
            'DateModified': '2026-10-17T14:52:45.0425985Z',
          },
        ],
      },
      '/System/Logs/a%20b.txt': 'log text',
    });
    final api = EmbyAdminSystemApi(fake.dio);

    final logs = await api.getLogFiles();
    expect(logs.single.name, 'embyserver.txt');
    expect(await api.getLogFileContent('a b.txt'), 'log text');
  });

  test('activity log sends only the filters Emby has', () async {
    final fake = AdminFake({
      '/System/ActivityLog/Entries': {
        'Items': [
          {
            'Id': 16,
            'Name': 'n',
            'Type': 'user.passwordchanged',
            'Date': '2026-10-17T14:45:58.6710000Z',
            'UserId': '2',
            'Severity': 'Warn',
          },
        ],
        'TotalRecordCount': 1,
      },
    });
    final result = await EmbyAdminSystemApi(fake.dio).getActivityLog(
      startIndex: 0,
      limit: 5,
      hasUserId: true,
      minDate: DateTime.utc(2026, 10, 1),
      maxDate: DateTime.utc(2026, 10, 2),
      severity: 'Error',
      username: 'claude',
    );

    expect(fake.last.queryParameters, {
      'StartIndex': 0,
      'Limit': 5,
      'HasUserId': true,
      'MinDate': '2026-10-01T00:00:00.000Z',
    });
    expect(result.items.single.id, '16');
    expect(result.items.single.userId, '2');
    expect(result.items.single.severity, 'Warning');
  });

  test('named configuration posts to its key', () async {
    final fake = AdminFake();
    await EmbyAdminSystemApi(
      fake.dio,
    ).updateNamedConfiguration('cinemamode', {'EnableIntrosForMovies': true});

    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/System/Configuration/cinemamode');
    expect(fake.last.data, {'EnableIntrosForMovies': true});
  });

  test('no password reset providers or splashscreen', () async {
    final fake = AdminFake();
    final api = EmbyAdminSystemApi(fake.dio);

    expect(await api.getPasswordResetProviders(), isEmpty);
    expect(
      () => api.uploadSplashscreen([1], 'image/png'),
      throwsUnsupportedError,
    );
    expect(api.deleteSplashscreen, throwsUnsupportedError);
    expect(fake.requests, isEmpty);
  });
}
