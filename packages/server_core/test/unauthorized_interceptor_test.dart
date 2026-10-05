import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

void main() {
  group('UnauthorizedInterceptor', () {
    late HttpServer server;
    late Dio dio;
    late List<String> requestedPaths;

    // Returns 401 for every request until [failCount] requests have been
    // answered, then 200 with {'ok': true} for every one after that.
    Future<void> serveWithFailures(int failCount) async {
      var seen = 0;
      server.listen((request) async {
        requestedPaths.add(request.uri.path);
        seen++;
        if (seen <= failCount) {
          request.response.statusCode = HttpStatus.unauthorized;
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'ok': true}));
        }
        await request.response.close();
      });
    }

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      requestedPaths = [];
      dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
    });

    tearDown(() async {
      dio.close(force: true);
      await server.close(force: true);
    });

    test(
      'retries once and resolves when onUnauthorized reports recovery',
      () async {
        await serveWithFailures(1);
        var calls = 0;
        dio.interceptors.add(UnauthorizedInterceptor(
          dio,
          onUnauthorized: () async {
            calls++;
            return true;
          },
        ));

        final response = await dio.get<Map<String, dynamic>>('/Items');

        expect(response.statusCode, 200);
        expect(response.data, {'ok': true});
        expect(calls, 1);
        expect(requestedPaths, ['/Items', '/Items']);
      },
    );

    test(
      'reports the 401 unchanged when onUnauthorized cannot recover',
      () async {
        await serveWithFailures(99);
        var calls = 0;
        dio.interceptors.add(UnauthorizedInterceptor(
          dio,
          onUnauthorized: () async {
            calls++;
            return false;
          },
        ));

        await expectLater(
          dio.get<void>('/Items'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        expect(calls, 1);
        // Never retried: exactly the first request reached the server.
        expect(requestedPaths, ['/Items']);
      },
    );

    test('never retries the retried request itself', () async {
      // Every request 401s, including the retry.
      await serveWithFailures(99);
      dio.interceptors.add(UnauthorizedInterceptor(
        dio,
        onUnauthorized: () async => true,
      ));

      await expectLater(
        dio.get<void>('/Items'),
        throwsA(isA<DioException>()),
      );
      // Exactly two requests reached the server: the original, and one
      // retry — never a second retry looping forever.
      expect(requestedPaths, ['/Items', '/Items']);
    });

    test(
      'coalesces concurrent 401s into a single recovery attempt',
      () async {
        await serveWithFailures(2);
        var calls = 0;
        final gate = Completer<bool>();
        dio.interceptors.add(UnauthorizedInterceptor(
          dio,
          onUnauthorized: () {
            calls++;
            return gate.future;
          },
        ));

        final first = dio.get<void>('/Items');
        final second = dio.get<void>('/Items/2');
        // Let both requests land their 401s before recovery resolves.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        gate.complete(true);

        await Future.wait([first, second]);
        expect(calls, 1);
      },
    );

    test('a non-401 error is left alone', () async {
      server.listen((request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });
      var calls = 0;
      dio.interceptors.add(UnauthorizedInterceptor(
        dio,
        onUnauthorized: () async {
          calls++;
          return true;
        },
      ));

      await expectLater(
        dio.get<void>('/Items'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
      expect(calls, 0);
    });
  });
}
