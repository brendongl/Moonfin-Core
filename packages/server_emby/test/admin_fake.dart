import 'package:dio/dio.dart';

/// Records each request and answers it from [responses], keyed by path, or
/// with an empty map. A path in [statuses] fails with that status instead.
class AdminFake extends Interceptor {
  AdminFake([Map<String, Object?>? responses]) : responses = responses ?? {};

  final Map<String, Object?> responses;
  final Map<String, int> statuses = {};
  final List<RequestOptions> requests = [];

  RequestOptions get last => requests.last;

  Dio get dio => Dio()..interceptors.add(this);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final status = statuses[options.path];
    final response = Response<Object?>(
      requestOptions: options,
      statusCode: status ?? 200,
      data: responses[options.path] ?? <String, dynamic>{},
    );
    if (status == null) return handler.resolve(response);
    handler.reject(
      DioException.badResponse(
        statusCode: status,
        requestOptions: options,
        response: response,
      ),
    );
  }
}
