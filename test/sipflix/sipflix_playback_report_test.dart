import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_playback_report.dart';

void main() {
  Future<void> check(
    SipflixPlaybackReportController controller, {
    String key = 'session-1',
  }) => controller.check(
    failureKey: key,
    token: 'viewer-secret',
    userId: 'u1',
    itemId: '6',
    mediaSourceId: 'src6',
    playMethod: 'transcode',
    httpStatus: 500,
    appVersion: '2.4.0-test',
  );

  testWidgets('pending polls are bounded and reuse one attempt ID', (
    tester,
  ) async {
    final attempts = <String>[];
    final controller = SipflixPlaybackReportController(
      endpoint: 'https://relay.example/v1/playback-failures',
      post: (event, token, cancel) async {
        attempts.add(event['attemptId'] as String);
        return {'diagnosis': 'checking', 'reportStatus': 'pending'};
      },
    );
    addTearDown(controller.dispose);
    final work = check(controller);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await work;
    expect(attempts.length, 3);
    expect(attempts.toSet().length, 1);
    expect(controller.checking, isFalse);
    expect(controller.result!.reported, isFalse);
  });

  testWidgets(
    'overall deadline cancels a hung report without claiming success',
    (tester) async {
      final never = Completer<Map<String, dynamic>>();
      late CancelToken cancel;
      final controller = SipflixPlaybackReportController(
        endpoint: 'https://relay.example/v1/playback-failures',
        post: (event, token, requestCancel) {
          cancel = requestCancel;
          return never.future;
        },
      );
      addTearDown(controller.dispose);
      final work = check(controller);
      await tester.pump(const Duration(seconds: 46));
      await work;
      expect(cancel.isCancelled, isTrue);
      expect(controller.checking, isFalse);
      expect(controller.result!.reported, isFalse);
    },
  );

  test('rejects plaintext and token-bearing endpoint URLs', () async {
    for (final url in [
      '',
      'http://relay.example/v1',
      'https://relay.example/v1?key=secret',
      'https://user:secret@relay.example/v1',
    ]) {
      final controller = SipflixPlaybackReportController(endpoint: url);
      addTearDown(controller.dispose);
      expect(controller.enabled, isFalse);
      await check(controller);
      expect(controller.checking, isFalse);
      expect(controller.result, isNull);
    }
  });

  test(
    'one terminal attempt sends once and keeps credentials out of the payload',
    () async {
      var calls = 0;
      final pending = Completer<Map<String, dynamic>>();
      final controller = SipflixPlaybackReportController(
        endpoint: 'https://relay.example/v1/playback-failures',
        post: (event, token, cancel) {
          calls++;
          expect(token, 'viewer-secret');
          expect(event.values, isNot(contains('viewer-secret')));
          expect(event.keys, isNot(contains('url')));
          expect(event['mediaSourceId'], 'src6');
          return pending.future;
        },
      );
      addTearDown(controller.dispose);
      final first = check(controller);
      await check(controller);
      expect(calls, 1);
      expect(controller.checking, isTrue);
      pending.complete({
        'diagnosis': 'missing',
        'reportStatus': 'replacement_requested',
        'issueId': 70,
      });
      await first;
      expect(controller.checking, isFalse);
      expect(controller.result!.reported, isTrue);
      expect(controller.result!.message, contains('Report #70'));
      await check(controller);
      expect(calls, 1);
    },
  );

  test(
    'late old-episode report cannot replace the next episode result',
    () async {
      final old = Completer<Map<String, dynamic>>();
      var calls = 0;
      final controller = SipflixPlaybackReportController(
        endpoint: 'https://relay.example/v1/playback-failures',
        post: (event, token, cancel) async {
          calls++;
          if (calls == 1) return old.future;
          return {'diagnosis': 'source_readable', 'reportStatus': 'not_sent'};
        },
      );
      addTearDown(controller.dispose);
      final first = check(controller);
      await check(controller, key: 'session-2');
      old.complete({
        'diagnosis': 'missing',
        'reportStatus': 'reported',
        'issueId': 70,
      });
      await first;
      expect(controller.result!.diagnosis, 'source_readable');
      expect(controller.result!.reported, isFalse);
    },
  );

  test('disposal cancels the request and ignores late completion', () async {
    final pending = Completer<Map<String, dynamic>>();
    late CancelToken requestCancel;
    final controller = SipflixPlaybackReportController(
      endpoint: 'https://relay.example/v1/playback-failures',
      post: (event, token, cancel) {
        requestCancel = cancel;
        return pending.future;
      },
    );
    final first = check(controller);
    controller.dispose();
    expect(requestCancel.isCancelled, isTrue);
    pending.complete({
      'diagnosis': 'missing',
      'reportStatus': 'reported',
      'issueId': 70,
    });
    await first;
    expect(controller.result, isNull);
  });

  test('a timed out POST is not retried or described as reported', () async {
    var calls = 0;
    final controller = SipflixPlaybackReportController(
      endpoint: 'https://relay.example/v1/playback-failures',
      post: (event, token, cancel) async {
        calls++;
        throw TimeoutException('timeout');
      },
    );
    addTearDown(controller.dispose);
    await check(controller);
    expect(calls, 1);
    expect(controller.result!.reported, isFalse);
    expect(controller.result!.message, contains('couldn’t confirm'));
  });

  test(
    'missing file with failed report never tells customer no need to contact support',
    () {
      for (final status in [
        'auth_required',
        'uncertain',
        'unavailable',
        'needs_review',
      ]) {
        final result = SipflixPlaybackReportResult.fromJson({
          'diagnosis': 'missing',
          'reportStatus': status,
        });
        expect(result.isMissing, isTrue);
        expect(result.reported, isFalse);
        expect(result.message, contains('could not confirm'));
        expect(result.message, isNot(contains('don’t need')));
      }
    },
  );

  test('success without a real issue ID cannot be presented as success', () {
    for (final id in [null, '70', -1, 0]) {
      final result = SipflixPlaybackReportResult.fromJson({
        'diagnosis': 'missing',
        'reportStatus': 'reported',
        'issueId': id,
      });
      expect(result.reported, isFalse);
    }
  });
}
