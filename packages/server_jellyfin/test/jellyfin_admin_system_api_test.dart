import 'package:dio/dio.dart';
import 'package:server_jellyfin/src/api/jellyfin_admin_system_api.dart';
import 'package:test/test.dart';

class _FakeServer extends Interceptor {
  _FakeServer(this.handle);

  final void Function(RequestOptions options, RequestInterceptorHandler handler)
  handle;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handle(options, handler);
}

void main() {
  RequestOptions? request;
  late JellyfinAdminSystemApi api;

  setUp(() {
    request = null;
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          request = options;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'Items': [], 'TotalRecordCount': 0},
          ));
        }),
      );
    api = JellyfinAdminSystemApi(dio);
  });

  test('activity filters go to the server as query parameters', () async {
    await api.getActivityLog(
      startIndex: 25,
      limit: 25,
      hasUserId: true,
      minDate: DateTime.utc(2026, 10, 1),
      maxDate: DateTime.utc(2026, 10, 5, 23, 59, 59),
      severity: 'Critical',
      username: 'axl',
    );

    expect(request?.path, '/System/ActivityLog/Entries');
    expect(request?.queryParameters, {
      'startIndex': 25,
      'limit': 25,
      'hasUserId': true,
      'minDate': '2026-10-01T00:00:00.000Z',
      'maxDate': '2026-10-05T23:59:59.000Z',
      'severity': 'Critical',
      'username': 'axl',
    });
  });

  test('unset filters are left out', () async {
    await api.getActivityLog(startIndex: 0, limit: 4);

    expect(request?.queryParameters, {'startIndex': 0, 'limit': 4});
  });
}
