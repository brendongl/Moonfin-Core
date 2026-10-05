import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/friendly_error_message.dart';

DioException _dioError({
  int? statusCode,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final requestOptions = RequestOptions(path: '/test');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    response: statusCode == null
        ? null
        : Response(requestOptions: requestOptions, statusCode: statusCode),
  );
}

void main() {
  group('friendlyErrorMessage', () {
    test('never contains the raw DioException text', () {
      final error = _dioError(statusCode: 401);
      // Sipflix swarm R5/R6 bug B2: this is the exact shape ("DioException
      // [bad response]: ... status code of 401 ...") that reached the
      // viewer verbatim.
      expect(error.toString(), contains('DioException'));
      expect(friendlyErrorMessage(error), isNot(contains('DioException')));
      expect(friendlyErrorMessage(error), isNot(contains('status code')));
    });

    test('maps 401 and 403 to a plain sign-in-again message', () {
      expect(
        friendlyErrorMessage(_dioError(statusCode: 401)),
        "You've been signed out. Please sign in again.",
      );
      expect(
        friendlyErrorMessage(_dioError(statusCode: 403)),
        "You've been signed out. Please sign in again.",
      );
    });

    test('maps 404/410 to a not-found message', () {
      expect(
        friendlyErrorMessage(_dioError(statusCode: 404)),
        contains('could not be found'),
      );
      expect(
        friendlyErrorMessage(_dioError(statusCode: 410)),
        contains('could not be found'),
      );
    });

    test('maps 429 to a rate-limit message', () {
      expect(
        friendlyErrorMessage(_dioError(statusCode: 429)),
        contains('limiting requests'),
      );
    });

    test('maps 5xx to a server-problem message including the status', () {
      expect(
        friendlyErrorMessage(_dioError(statusCode: 503)),
        contains('error 503'),
      );
    });

    test('maps connection/timeout errors to actionable text', () {
      expect(
        friendlyErrorMessage(
          _dioError(type: DioExceptionType.connectionTimeout),
        ),
        contains('taking too long'),
      );
      expect(
        friendlyErrorMessage(
          _dioError(type: DioExceptionType.connectionError),
        ),
        contains('Could not reach the server'),
      );
    });

    test('falls back to the generic message for anything else', () {
      expect(
        friendlyErrorMessage(StateError('boom')),
        'Something went wrong. Please try again.',
      );
      expect(
        friendlyErrorMessage(StateError('boom'), fallback: 'Custom fallback'),
        'Custom fallback',
      );
    });
  });
}
