import 'dart:async';

import 'package:dio/dio.dart';

/// Routes every 401 a server's Dio client receives through one recovery
/// callback instead of each call site inventing its own retry/sign-out
/// handling — which is how a raw `DioException [bad response]: ... status
/// code of 401 ...` ended up on screen verbatim, progress reports kept
/// throwing unhandled async 401s every 5 seconds, and only a full app
/// restart actually recovered (Sipflix swarm R5/R6 bug B2).
///
/// [onUnauthorized] is called at most once per concurrent batch of 401s —
/// several in-flight requests, or the 5-second progress-report timer,
/// losing their token at the same moment are coalesced into a single
/// recovery attempt rather than one per request. It should return true when
/// it refreshed the active token (the failed request is then retried once
/// with it), or false when the viewer must sign in again (by then
/// [onUnauthorized] is expected to have already started that). A request is
/// retried at most once: a 401 on the retry itself is reported upward
/// unchanged, never looped.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor(this._dio, {required this.onUnauthorized});

  final Dio _dio;
  final Future<bool> Function() onUnauthorized;

  static const _retriedKey = 'sipflixUnauthorizedRetried';

  Future<bool>? _pendingRecovery;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final alreadyRetried = err.requestOptions.extra[_retriedKey] == true;
    if (err.response?.statusCode != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }
    unawaited(_recoverAndRetry(err, handler));
  }

  Future<void> _recoverAndRetry(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    bool recovered;
    try {
      recovered = await (_pendingRecovery ??= _runRecovery());
    } catch (_) {
      recovered = false;
    }
    if (!recovered) {
      handler.next(err);
      return;
    }

    final options = err.requestOptions;
    try {
      final response = await _dio.request<dynamic>(
        options.path,
        data: options.data,
        queryParameters: options.queryParameters,
        options: Options(
          method: options.method,
          headers: options.headers,
          responseType: options.responseType,
          contentType: options.contentType,
          extra: {...options.extra, _retriedKey: true},
        ),
      );
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<bool> _runRecovery() {
    final future = onUnauthorized();
    _pendingRecovery = future;
    unawaited(future.whenComplete(() {
      if (identical(_pendingRecovery, future)) {
        _pendingRecovery = null;
      }
    }));
    return future;
  }
}
