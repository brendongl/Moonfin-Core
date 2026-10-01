import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:moonfin/util/tv_image_cache_io.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  test('reads an error reply so its connection is released', () async {
    var bodyRead = false;
    final body = StreamController<List<int>>(onListen: () => bodyRead = true);
    final service = ImageFileService(
      httpClient: _FakeClient(
        (_) async => http.StreamedResponse(body.stream, 404),
      ),
    );

    final response = await service.get('https://example.test/poster.jpg');
    await Future<void>.delayed(Duration.zero);

    expect(response.statusCode, 404);
    expect(bodyRead, isTrue);
    await body.close();
  });

  test('gives up on a reply whose headers never arrive', () async {
    final service = ImageFileService(
      httpClient: _FakeClient((_) => Completer<http.StreamedResponse>().future),
      headerTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      service.get('https://example.test/poster.jpg'),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('fails a body that goes quiet part way through', () async {
    final body = StreamController<List<int>>();
    final service = ImageFileService(
      httpClient: _FakeClient(
        (_) async => http.StreamedResponse(body.stream, 200),
      ),
      bodyIdleTimeout: const Duration(milliseconds: 50),
    );

    final response = await service.get('https://example.test/poster.jpg');
    body.add([1, 2, 3]);

    await expectLater(
      response.content.drain<void>(),
      throwsA(isA<TimeoutException>()),
    );
    await body.close();
  });
}
