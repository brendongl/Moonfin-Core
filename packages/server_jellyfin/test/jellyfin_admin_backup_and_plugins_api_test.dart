import 'package:dio/dio.dart';
import 'package:server_jellyfin/src/api/jellyfin_admin_backup_api.dart';
import 'package:server_jellyfin/src/api/jellyfin_admin_plugins_api.dart';
import 'package:test/test.dart';

class _FakeServer extends Interceptor {
  _FakeServer(this.status, [this.body]);

  final int status;
  final Object? body;
  final requests = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final response =
        Response(requestOptions: options, statusCode: status, data: body);
    if (status >= 400) {
      handler.reject(
        DioException.badResponse(
          statusCode: status,
          requestOptions: options,
          response: response,
        ),
      );
    } else {
      handler.resolve(response);
    }
  }
}

Dio _dio(_FakeServer server) => Dio(
  BaseOptions(receiveTimeout: const Duration(seconds: 30)),
)..interceptors.add(server);

void main() {
  group('backups', () {
    test('create waits far past the client receive timeout', () async {
      final server = _FakeServer(200, {'Path': '/backups/a.zip'});
      final api = JellyfinAdminBackupApi(_dio(server));

      final manifest = await api.createBackup({'Metadata': false});

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/Backup/Create');
      expect(request.data, {'Metadata': false});
      expect(request.receiveTimeout, greaterThan(const Duration(hours: 1)));
      expect(manifest['Path'], '/backups/a.zip');
    });

    test('a restore 404 is thrown, not retried on other paths', () async {
      final server = _FakeServer(404);
      final api = JellyfinAdminBackupApi(_dio(server));

      await expectLater(
        api.restoreBackup('/backups/gone.zip'),
        throwsA(isA<DioException>()),
      );
      expect(server.requests.map((r) => r.path), ['/Backup/Restore']);
      expect(server.requests.single.data, {
        'ArchiveFileName': '/backups/gone.zip',
      });
    });

    test('list and manifest use the Backup routes only', () async {
      final server = _FakeServer(404);
      final api = JellyfinAdminBackupApi(_dio(server));

      await expectLater(api.getBackups(), throwsA(isA<DioException>()));
      await expectLater(
        api.getBackupManifest('a.zip'),
        throwsA(isA<DioException>()),
      );
      expect(server.requests.map((r) => r.path), [
        '/Backup',
        '/Backup/Manifest',
      ]);
      expect(server.requests.last.queryParameters, {'path': 'a.zip'});
    });
  });

  group('plugins', () {
    test('configuration pages come from the authenticated client', () async {
      final server = _FakeServer(200, [
        {'Name': 'TMDb', 'EnableInMainMenu': false, 'PluginId': 'b871'},
      ]);
      final api = JellyfinAdminPluginsApi(_dio(server));

      final pages = await api.getConfigurationPages();

      expect(server.requests.single.method, 'GET');
      expect(server.requests.single.path, '/web/ConfigurationPages');
      expect(pages.single['Name'], 'TMDb');
    });
  });
}
