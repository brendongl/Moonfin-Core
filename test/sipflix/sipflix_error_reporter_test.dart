import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_error_reporter.dart';

void main() {
  test('removes credentials, headers and capability URLs', () {
    final out = SipflixErrorReporter.redact(
      'password="secret words" Pw=hidden Authorization: Bearer abcdef https://host/seed/private?api_key=more',
    );
    for (final secret in [
      'secret words',
      'hidden',
      'abcdef',
      'private',
      'more',
    ]) {
      expect(out, isNot(contains(secret)));
    }
  });
  test('removes quoted JSON headers, cookies and alternate password keys', () {
    final out = SipflixErrorReporter.redact(
      '{"Authorization":"Bearer auth-secret","Cookie":"session=cookie-secret; second=second-secret","Pw":"pw-secret","passwd":"pass-secret","x-mediabrowser-token":"media-secret"}',
    );
    for (final secret in [
      'auth-secret',
      'cookie-secret',
      'second-secret',
      'pw-secret',
      'pass-secret',
      'media-secret',
    ]) {
      expect(out, isNot(contains(secret)));
    }
    expect(
      SipflixErrorReporter.redact('Cookie: a=cookie-secret; b=second-secret'),
      isNot(contains('secret')),
    );
    expect(
      SipflixErrorReporter.redact('failed ?api_key=query-secret'),
      isNot(contains('query-secret')),
    );
  });
  test('metadata and diagnostic fields fit the relay schema', () async {
    final events = <Map<String, dynamic>>[];
    final reporter = SipflixErrorReporter(
      post: (event) async {
        events.add(event);
      },
      metadata: () async => {
        'deviceName': 'n' * 500,
        'androidId': 'i' * 500,
        'appVersion': 'v' * 500,
      },
    );
    await reporter.report(
      category: 'c' * 500,
      message: 'failure',
      code: 'x' * 500,
      server: 's' * 500,
      route: 'r' * 500,
    );
    for (final field in ['category', 'code', 'appVersion']) {
      expect((events.single[field] as String).length, 64);
    }
    for (final field in ['deviceName', 'androidId', 'server']) {
      expect((events.single[field] as String).length, 128);
    }
    expect((events.single['route'] as String).length, 256);
  });
  test(
    'bounds report text length',
    () => expect(SipflixErrorReporter.redact('x' * 5000).length, 1000),
  );
  test('dedupes a burst then allows the same error after a minute', () async {
    var now = DateTime(2026);
    final events = <Map<String, dynamic>>[];
    final reporter = SipflixErrorReporter(
      post: (event) async {
        events.add(event);
      },
      metadata: () async => {
        'deviceName': 'test',
        'androidId': 'test-id',
        'appVersion': 'test',
      },
      now: () => now,
    );
    Future<void> send() => reporter.report(
      category: 'network',
      message: 'Failed',
      code: '500',
      server: 'Delta',
      route: 'Direct',
    );
    await send();
    await send();
    expect(events.length, 1);
    now = now.add(const Duration(minutes: 1));
    await send();
    expect(events.length, 2);
    expect(
      events.first.keys,
      containsAll([
        'deviceName',
        'androidId',
        'appVersion',
        'category',
        'message',
        'code',
        'server',
        'route',
        'timestamp',
      ]),
    );
  });
  test('caps unique errors at ten a minute', () async {
    var calls = 0;
    final reporter = SipflixErrorReporter(
      post: (_) async {
        calls++;
      },
      metadata: () async => {},
    );
    for (var i = 0; i < 20; i++) {
      await reporter.report(
        category: 'test',
        message: 'failure $i',
        code: '500',
        server: 'Alpha',
        route: 'CDN 1',
      );
    }
    expect(calls, 10);
  });
  test('caps concurrent posts at two and does not queue more', () async {
    final release = Completer<void>();
    var calls = 0;
    final reporter = SipflixErrorReporter(
      post: (_) async {
        calls++;
        await release.future;
      },
      metadata: () async => {},
    );
    final sends = [
      for (var i = 0; i < 20; i++)
        reporter.report(
          category: 'test',
          message: 'failure $i',
          code: '500',
          server: 'Alpha',
          route: 'CDN 1',
        ),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    release.complete();
    await Future.wait(sends);
  });
  test(
    'failed delivery is swallowed without retries or recursive logging',
    () async {
      var calls = 0;
      final reporter = SipflixErrorReporter(
        post: (_) async {
          calls++;
          throw StateError('offline');
        },
        metadata: () async => {},
      );
      await reporter.report(
        category: 'test',
        message: 'failure',
        code: '500',
        server: 'Alpha',
        route: 'CDN 1',
      );
      expect(calls, 1);
    },
  );
}
