import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_login_server.dart';

void main() {
  Future<(int, String)> submit(SipflixLoginServer server) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.listeningPort}/login'),
      );
      req.write('username=test&password=test');
      final response = await req.close();
      return (response.statusCode, await utf8.decoder.bind(response).join());
    } finally {
      client.close(force: true);
    }
  }

  test('LAN timeout is never a successful sign-in', () async {
    final server = SipflixLoginServer(
      serverName: 'Test',
      responseTimeout: const Duration(milliseconds: 10),
      onCredentials: (_, _) => Completer<String?>().future,
    );
    await server.start(bindPort: 0);
    addTearDown(server.stop);
    final result = await submit(server);
    expect(result.$1, isNot(200));
    expect(result.$2, contains('not a confirmed sign-in'));
  });
  test('closed screen rejects new requests during delayed shutdown', () async {
    var calls = 0;
    final server = SipflixLoginServer(
      serverName: 'Test',
      onCredentials: (_, _) async {
        calls++;
        return null;
      },
    );
    await server.start(bindPort: 0);
    addTearDown(server.stop);
    server.stopAccepting();
    final result = await submit(server);
    expect(result.$1, 410);
    expect(calls, 0);
  });
  test('only completed successful callback gets OK', () async {
    final completion = Completer<String?>();
    final server = SipflixLoginServer(
      serverName: 'Test',
      onCredentials: (_, _) => completion.future,
    );
    await server.start(bindPort: 0);
    addTearDown(server.stop);
    final pending = submit(server);
    completion.complete(null);
    expect(await pending, (200, 'OK'));
  });
}
