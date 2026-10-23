import 'package:dio/dio.dart';
import 'package:server_jellyfin/src/api/jellyfin_admin_users_api.dart';
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
  late List<RequestOptions> requests;
  late int Function(RequestOptions) status;
  late Object? Function(RequestOptions) body;
  late JellyfinAdminUsersApi api;

  setUp(() {
    requests = [];
    status = (_) => 204;
    body = (_) => null;
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          requests.add(options);
          final code = status(options);
          final response = Response(
            requestOptions: options,
            statusCode: code,
            data: body(options),
          );
          if (code >= 400) {
            handler.reject(DioException.badResponse(
              statusCode: code,
              requestOptions: options,
              response: response,
            ));
          } else {
            handler.resolve(response);
          }
        }),
      );
    api = JellyfinAdminUsersApi(dio);
  });

  test('updateUser posts the whole UserDto to /Users?userId=', () async {
    final dto = {
      'Name': 'kid',
      'Id': 'u1',
      'Configuration': {'SubtitleMode': 'Smart', 'CastReceiverId': 'F007D354'},
    };
    await api.updateUser('u1', dto);

    expect(requests.single.method, 'POST');
    expect(requests.single.path, '/Users');
    expect(requests.single.queryParameters, {'userId': 'u1'});
    expect(requests.single.data, dto);
  });

  test('a password change uses /Users/Password and sends CurrentPw', () async {
    await api.updateUserPassword('u1', currentPassword: 'old', newPassword: 'new');

    expect(requests.single.path, '/Users/Password');
    expect(requests.single.queryParameters, {'userId': 'u1'});
    expect(requests.single.data,
        {'CurrentPw': 'old', 'NewPw': 'new', 'ResetPassword': false});
  });

  test('a server without /Users/Password gets the older route', () async {
    status = (o) => o.path == '/Users/Password' ? 404 : 204;
    await api.updateUserPassword('u1', resetPassword: true);

    expect(requests.map((r) => r.path), ['/Users/Password', '/Users/u1/Password']);
    expect(requests.last.data, {'ResetPassword': true});
  });

  test('a refused current password is not retried', () async {
    status = (_) => 403;
    await expectLater(
      api.updateUserPassword('u1', currentPassword: 'bad', newPassword: 'x'),
      throwsA(isA<DioException>()),
    );
    expect(requests, hasLength(1));
  });

  test('getChannels reads the items and passes the deletion filter', () async {
    status = (_) => 200;
    body = (_) => {
          'Items': [
            {'Id': 'c1', 'Name': 'Podcasts'},
          ],
          'TotalRecordCount': 1,
        };
    final channels = await api.getChannels(supportsMediaDeletion: true);

    expect(requests.single.path, '/Channels');
    expect(requests.single.queryParameters, {'supportsMediaDeletion': true});
    expect(channels, [
      {'Id': 'c1', 'Name': 'Podcasts'},
    ]);
  });
}
