import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/src/api/jellyfin_admin_items_api.dart';
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
  test('refresh always names both modes', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          request = options;
          handler.resolve(Response(requestOptions: options, statusCode: 204));
        }),
      );

    await JellyfinAdminItemsApi(dio).refreshItem('movie-1');

    expect(request?.method, 'POST');
    expect(request?.path, '/Items/movie-1/Refresh');
    expect(request?.queryParameters['MetadataRefreshMode'], 'Default');
    expect(request?.queryParameters['ImageRefreshMode'], 'Default');
  });

  test('replacing everything asks every provider again', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          request = options;
          handler.resolve(Response(requestOptions: options, statusCode: 204));
        }),
      );

    await JellyfinAdminItemsApi(dio).refreshItem(
      'movie-1',
      replaceAllMetadata: true,
      replaceAllImages: true,
      metadataRefreshMode: MetadataRefreshMode.fullRefresh,
      imageRefreshMode: MetadataRefreshMode.fullRefresh,
    );

    expect(request?.queryParameters, {
      'MetadataRefreshMode': 'FullRefresh',
      'ImageRefreshMode': 'FullRefresh',
      'ReplaceAllMetadata': true,
      'ReplaceAllImages': true,
    });
  });

  test('a trickplay rebuild is sent as RegenerateTrickplay', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          request = options;
          handler.resolve(Response(requestOptions: options, statusCode: 204));
        }),
      );

    await JellyfinAdminItemsApi(dio).refreshItem(
      'movie-1',
      regenerateTrickplay: true,
      metadataRefreshMode: MetadataRefreshMode.fullRefresh,
      imageRefreshMode: MetadataRefreshMode.fullRefresh,
    );

    expect(request?.queryParameters['RegenerateTrickplay'], true);
  });

  // The server's only update route is a POST, there's no PUT.
  test('a missing item fails on its POST and is not retried', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          requests.add(options);
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 404),
              type: DioExceptionType.badResponse,
            ),
          );
        }),
      );

    await expectLater(
      JellyfinAdminItemsApi(dio).updateItem('gone', {'Id': 'gone'}),
      throwsA(isA<DioException>()),
    );
    expect(requests.map((r) => '${r.method} ${r.path}'), ['POST /Items/gone']);
  });

  test('identify uses the routes the server has', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          requests.add(options);
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: const []),
          );
        }),
      );
    final api = JellyfinAdminItemsApi(dio);

    await api.searchRemote('musicvideo', {'SearchInfo': {'Name': 'x'}});
    await api.applyRemoteSearchResult('id-1', {'Name': 'x'},
        replaceAllImages: false);
    await api.getExternalIdInfos('id-1');

    expect(requests.map((r) => '${r.method} ${r.path}'), [
      'POST /Items/RemoteSearch/MusicVideo',
      'POST /Items/RemoteSearch/Apply/id-1',
      'GET /Items/id-1/ExternalIdInfos',
    ]);
    expect(requests[1].queryParameters, {'replaceAllImages': false});
  });
}
