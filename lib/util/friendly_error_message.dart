import 'package:dio/dio.dart';

/// Turns a caught error into plain text safe to show a viewer.
///
/// Safety net for every screen that used to call `error.toString()` and
/// show whatever a [DioException] (or any other exception) printed —
/// including the raw `DioException [bad response]: ... status code of 401
/// ...` stack-trace-style text that reached the player, Settings and detail
/// pages verbatim after a server-side token revoke (Sipflix swarm R5/R6 bug
/// B2). Call sites that already map their own specific cases (a 20s detail
/// load timeout, a 4K-refusal reason) should keep doing that and only fall
/// back to this for everything else.
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return "You've been signed out. Please sign in again.";
    }
    if (status == 404 || status == 410) {
      return 'This could not be found on the server.';
    }
    if (status == 429) {
      return 'The server is limiting requests. Please try again shortly.';
    }
    if (status != null && status >= 500) {
      return 'The server had a problem (error $status). Please try again.';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The server is taking too long to respond. Please try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your connection and try '
            'again.';
      case DioExceptionType.cancel:
        return fallback;
      case DioExceptionType.badCertificate:
        return 'Could not securely connect to the server.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return fallback;
    }
  }
  return fallback;
}
