import 'dart:convert';
import 'dart:io';

import 'package:server_core/server_core.dart';
import 'package:server_emby/server_emby.dart';
import 'package:test/test.dart';

/// Covers the response-side 4K post-filter in EmbyMediaServerClient
/// (_postFilterUhd): the mechanism that catches the list-shaped endpoints
/// Emby's own Is4K request filter can't reach — mixed Movie/Series grids
/// (Home rows, Favorites, Studio pages, Collections) and Shows/{id}/Episodes,
/// which isn't even matched by the request-time filter.
void main() {
  late HttpServer server;
  late EmbyMediaServerClient client;
  // Each test configures how the fake server answers the "page" request
  // (no Ids) vs. the probe request (has Ids) for a given path.
  late Map<String, dynamic> Function(Uri uri) pageResponder;
  late Map<String, dynamic> Function(Uri uri) probeResponder;
  late bool probeShouldFail;
  int probeCallCount = 0;

  setUp(() async {
    probeCallCount = 0;
    probeShouldFail = false;
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final uri = req.uri;
      final isProbe = uri.queryParameters.containsKey('Ids');
      if (isProbe) {
        probeCallCount++;
        if (probeShouldFail) {
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(probeResponder(uri)))
          ..close();
        return;
      }
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(pageResponder(uri)))
        ..close();
    });
    client = EmbyMediaServerClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      deviceInfo: const DeviceInfo(
          id: 't', name: 't', appName: 't', appVersion: '1'),
    )
      ..accessToken = 'x'
      ..userId = 'u1';
    EmbyMediaServerClient.hideStandalone4k = () => true;
  });

  tearDown(() async {
    EmbyMediaServerClient.hideStandalone4k = () => false;
    await server.close(force: true);
  });

  test('mixed-type page: 4K-only Movie dropped, Series and playable '
      'Episode kept, via one probe', () async {
    pageResponder = (uri) => {
          'Items': [
            {'Id': 'movie-4k', 'Type': 'Movie', 'Name': 'Pompeii'},
            {'Id': 'ep-ok', 'Type': 'Episode', 'Name': 'S1E1'},
            {'Id': 'series-1', 'Type': 'Series', 'Name': 'A Show'},
          ],
          'TotalRecordCount': 3,
        };
    probeResponder = (uri) {
      // Survivor probe: only ep-ok has a non-4K version.
      expect(uri.queryParameters['IncludeItemTypes'], 'Movie,Episode');
      expect(uri.queryParameters['Is4K'], 'false');
      final ids = uri.queryParameters['Ids']!.split(',');
      expect(ids.toSet(), {'movie-4k', 'ep-ok'});
      return {
        'Items': [
          {'Id': 'ep-ok', 'Type': 'Episode'},
        ],
      };
    };

    final data =
        await client.itemsApi.getItems(parentId: 'studio-1', recursive: true);
    final items = (data['Items'] as List).cast<Map>();
    expect(items.map((m) => m['Id']), ['ep-ok', 'series-1']);
    expect(data['TotalRecordCount'], 2);
    expect(probeCallCount, 1);
  });

  test('/Items/Latest bare-array response stays a bare array after '
      'filtering', () async {
    // getLatestItems() hits /Users/{id}/Items/Latest, whose raw HTTP body is
    // a bare JSON array (not {Items: [...]})."
    server.close(force: true);
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final uri = req.uri;
      if (uri.queryParameters.containsKey('Ids')) {
        probeCallCount++;
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'Items': []})) // nothing survives
          ..close();
        return;
      }
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode([
          {'Id': 'movie-4k', 'Type': 'Movie'},
          {'Id': 'series-1', 'Type': 'Series'},
        ]))
        ..close();
    });
    client = EmbyMediaServerClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      deviceInfo: const DeviceInfo(
          id: 't', name: 't', appName: 't', appVersion: '1'),
    )
      ..accessToken = 'x'
      ..userId = 'u1';

    final data = await client.itemsApi.getLatestItems();
    // getLatestItems() re-wraps the bare array into {Items, TotalRecordCount}
    // at the API layer; the point under test is that the *bare array HTTP
    // body* was filtered correctly before that re-wrap happened.
    final items = (data['Items'] as List).cast<Map>();
    expect(items.map((m) => m['Id']), ['series-1']);
    expect(probeCallCount, 1);
  });

  test('empty page makes no probe call', () async {
    pageResponder = (uri) => {'Items': <dynamic>[], 'TotalRecordCount': 0};
    probeResponder = (uri) => {'Items': []};

    final data =
        await client.itemsApi.getItems(parentId: 'studio-1', recursive: true);
    expect(data['Items'], isEmpty);
    expect(probeCallCount, 0);
  });

  test('page with only Series/Folder items makes no probe call', () async {
    pageResponder = (uri) => {
          'Items': [
            {'Id': 'series-1', 'Type': 'Series'},
            {'Id': 'folder-1', 'Type': 'Folder'},
          ],
          'TotalRecordCount': 2,
        };
    probeResponder = (uri) => {'Items': []};

    final data =
        await client.itemsApi.getItems(parentId: 'studio-1', recursive: true);
    final items = (data['Items'] as List).cast<Map>();
    expect(items.map((m) => m['Id']), ['series-1', 'folder-1']);
    expect(probeCallCount, 0);
  });

  test('probe failure fails open: original unfiltered items are kept',
      () async {
    pageResponder = (uri) => {
          'Items': [
            {'Id': 'movie-4k', 'Type': 'Movie'},
            {'Id': 'series-1', 'Type': 'Series'},
          ],
          'TotalRecordCount': 2,
        };
    probeShouldFail = true;

    final data =
        await client.itemsApi.getItems(parentId: 'studio-1', recursive: true);
    final items = (data['Items'] as List).cast<Map>();
    expect(items.map((m) => m['Id']), ['movie-4k', 'series-1']);
    expect(data['TotalRecordCount'], 2);
  });

  test('Shows/{id}/Episodes is covered by the post-filter even though it is '
      'not matched by the request-time Is4K filter', () async {
    server.close(force: true);
    server = await HttpServer.bind('127.0.0.1', 0);
    final seenPaths = <String>[];
    server.listen((req) async {
      seenPaths.add(req.uri.path);
      if (req.uri.queryParameters.containsKey('Ids')) {
        probeCallCount++;
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'Items': [
              {'Id': 'ep-1080p'},
            ]
          }))
          ..close();
        return;
      }
      // No Is4K param: confirms the request-time filter never fires for
      // this path.
      expect(req.uri.queryParameters.containsKey('Is4K'), isFalse);
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'Items': [
            {'Id': 'ep-2160p', 'Type': 'Episode'},
            {'Id': 'ep-1080p', 'Type': 'Episode'},
          ],
          'TotalRecordCount': 2,
        }))
        ..close();
    });
    client = EmbyMediaServerClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      deviceInfo: const DeviceInfo(
          id: 't', name: 't', appName: 't', appVersion: '1'),
    )
      ..accessToken = 'x'
      ..userId = 'u1';

    final data = await client.itemsApi.getEpisodes('series-1');
    final items = (data['Items'] as List).cast<Map>();
    expect(items.map((m) => m['Id']), ['ep-1080p']);
    expect(probeCallCount, 1);
  });

  test('Favorites (IsFavorite=true) is still post-filtered even though the '
      'request-time filter already added Is4K=false — fix for the Max29 '
      'Favorites leak ("Pompeii: Disaster Street" 3549673, findings-FINAL): '
      'Emby does not reliably honour Is4K once IsFavorite is also on the '
      'request, so trusting the request-time flag skipped the post-filter '
      'and let the 4K-only favourite straight through', () async {
    server.close(force: true);
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final uri = req.uri;
      if (uri.queryParameters.containsKey('Ids')) {
        probeCallCount++;
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'Items': [
              {'Id': 'michael'},
            ],
          }))
          ..close();
        return;
      }
      // The request-time filter (_carries4kFlag) does add Is4K=false here,
      // since this is a typed Movie favourites query — but the fake server
      // deliberately ignores it, the way Delta does for IsFavorite queries,
      // to prove the post-filter still has to catch it.
      expect(uri.queryParameters['Is4K'], 'false');
      expect(uri.queryParameters['IsFavorite'], 'true');
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'Items': [
            {'Id': 'michael', 'Type': 'Movie'},
            {'Id': 'pompeii-4k', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 2,
        }))
        ..close();
    });
    client = EmbyMediaServerClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      deviceInfo: const DeviceInfo(
          id: 't', name: 't', appName: 't', appVersion: '1'),
    )
      ..accessToken = 'x'
      ..userId = 'u1';

    final data = await client.itemsApi.getItems(
      recursive: true,
      isFavorite: true,
      includeItemTypes: ['Movie'],
    );
    final items = (data['Items'] as List).cast<Map>();
    expect(items.map((m) => m['Id']), ['michael']);
    expect(data['TotalRecordCount'], 1);
    expect(probeCallCount, 1);
  });

  test('disabled on non-fragile devices: no probe, items unchanged',
      () async {
    EmbyMediaServerClient.hideStandalone4k = () => false;
    pageResponder = (uri) => {
          'Items': [
            {'Id': 'movie-4k', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 1,
        };
    probeResponder = (uri) => {'Items': []};

    final data =
        await client.itemsApi.getItems(parentId: 'studio-1', recursive: true);
    final items = (data['Items'] as List).cast<Map>();
    expect(items.map((m) => m['Id']), ['movie-4k']);
    expect(probeCallCount, 0);
  });
}
