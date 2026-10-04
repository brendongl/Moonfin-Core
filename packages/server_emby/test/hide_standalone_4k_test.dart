import 'dart:convert';
import 'dart:io';

import 'package:server_core/server_core.dart';
import 'package:server_emby/server_emby.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late List<Uri> seen;
  late EmbyMediaServerClient client;

  setUp(() async {
    seen = [];
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) {
      seen.add(req.uri);
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'Items': [], 'TotalRecordCount': 0}))
        ..close();
    });
    client = EmbyMediaServerClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      deviceInfo: const DeviceInfo(
          id: 't', name: 't', appName: 't', appVersion: '1'),
    )
      ..accessToken = 'x'
      ..userId = 'u1';
  });

  tearDown(() async {
    EmbyMediaServerClient.hideStandalone4k = () => false;
    await server.close(force: true);
  });

  test('adds Is4K=false on list queries when enabled', () async {
    EmbyMediaServerClient.hideStandalone4k = () => true;
    await client.itemsApi.getItems(
        recursive: true, searchTerm: 'x', includeItemTypes: ['Movie']);
    await client.itemsApi.getResumeItems();
    expect(seen.length, 2);
    for (final u in seen) {
      expect(u.queryParameters['Is4K'], 'false');
    }
  });

  test('does nothing when disabled', () async {
    await client.itemsApi.getItems(recursive: true);
    expect(seen.single.queryParameters.containsKey('Is4K'), isFalse);
  });

  test('explicit Ids lookups are never filtered', () async {
    EmbyMediaServerClient.hideStandalone4k = () => true;
    await client.itemsApi.getItems(ids: ['1']);
    expect(seen.single.queryParameters.containsKey('Is4K'), isFalse);
  });

  test('Series, BoxSet and untyped queries are never filtered', () async {
    EmbyMediaServerClient.hideStandalone4k = () => true;
    await client.itemsApi.getItems(recursive: true, includeItemTypes: ['Series']);
    await client.itemsApi.getItems(recursive: true, includeItemTypes: ['Movie', 'Series']);
    await client.itemsApi.getItems(recursive: true, searchTerm: 'x');
    expect(seen.length, 3);
    for (final u in seen) {
      expect(u.queryParameters.containsKey('Is4K'), isFalse);
    }
  });
}
