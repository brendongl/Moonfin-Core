import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations_en.dart';
import 'package:moonfin/sipflix/sipflix_error_message.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:moonfin/ui/util/error_message.dart';

void main() {
  final l10n = AppLocalizationsEn();
  DioException failure(int status, {String? url}) {
    final request = RequestOptions(
      path: url ?? 'https://emby2.n2.d-crypt.io/Items?api_key=SECRET',
      headers: {'Authorization': 'Bearer SECRET'},
      data: {'password': 'SECRET'},
    );
    return DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      message: 'password=SECRET',
      response: Response(
        requestOptions: request,
        statusCode: status,
        data: {'message': 'SECRET https://private.invalid'},
      ),
    );
  }

  test(
    'HTTP message names operation server route code and next step safely',
    () {
      final text = describeError(failure(503), l10n, operation: 'Load library');
      expect(text, contains('Load library on Delta via Direct'));
      expect(text, contains('HTTP 503'));
      expect(text, contains('Try again'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('Items')));
    },
  );
  test('all server routes recognized without leaking request URI', () {
    for (final server in SipflixServers.all) {
      for (final route in server.routes) {
        final text = SipflixErrorMessage.describe(
          failure(401, url: '${route.url}/Users?token=SECRET'),
        )!;
        expect(text, contains('${server.name} via ${route.label}'));
        expect(text, contains('Sign in again'));
        expect(text, isNot(contains('SECRET')));
      }
    }
  });
  test('explicit context preserves timeout information for library/favorites/search', () {
    for (final op in [
      'Load library',
      'Load favorites',
      'Search',
      'Load more titles',
    ]) {
      final text = describeError(
        TimeoutException('SECRET'),
        l10n,
        serverRef: SipflixServers.delta.recordId,
        operation: op,
        networkError: true,
      );
      expect(text, contains('$op on Delta via saved route'));
      expect(text, contains('TIMEOUT'));
      expect(text, isNot(contains('SECRET')));
    }
  });
  test(
    'known origins with userinfo are matched but credentials never displayed',
    () {
      final text = SipflixErrorMessage.describe(
        failure(
          403,
          url: 'https://name:SECRET@emby2.n2.d-crypt.io/Items?password=SECRET',
        ),
      )!;
      expect(text, contains('Delta'));
      expect(text, contains('Message FlixBot'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('name:')));
    },
  );
  test('unknown hosts and lookalike suffixes retain upstream path', () {
    for (final host in [
      'other.invalid',
      'emby2.n2.d-crypt.io.attacker.invalid',
    ]) {
      expect(
        SipflixErrorMessage.describe(failure(503, url: 'https://$host/Items')),
        isNull,
      );
    }
    expect(
      describeError(TimeoutException('slow'), l10n),
      'Unable to connect to server',
    );
    expect(describeError(StateError('original'), l10n), 'Bad state: original');
  });
  test(
    'untrusted operation and opaque errors cannot become displayed secrets',
    () {
      final text = SipflixErrorMessage.describe(
        Exception('token=SECRET'),
        serverRef: SipflixServers.alphaV2.recordId,
        operation: 'SECRET',
      )!;
      expect(text, startsWith('Request on AlphaV2'));
      expect(text, contains('UNKNOWN'));
      expect(text, isNot(contains('SECRET')));
    },
  );
  test('TLS and cancellation have separate codes', () {
    for (final entry in {
      DioExceptionType.badCertificate: 'TLS',
      DioExceptionType.cancel: 'CANCELLED',
    }.entries) {
      final error = DioException(
        requestOptions: RequestOptions(path: '/Items'),
        type: entry.key,
      );
      expect(
        SipflixErrorMessage.describe(
          error,
          serverRef: SipflixServers.delta.recordId,
        ),
        contains(entry.value),
      );
    }
  });
}
