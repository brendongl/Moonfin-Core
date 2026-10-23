import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/di/providers.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_user_providers.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FailingTasksApi extends Fake implements AdminTasksApi {
  @override
  Future<List<Map<String, dynamic>>> getTasks({bool? isHidden}) =>
      Future.error(Exception('offline'));
}

class _FakeSocket implements ServerWebSocketClient {
  final _messages = StreamController<ServerWebSocketMessage>.broadcast();
  final _connections = StreamController<void>.broadcast();

  @override
  Stream<ServerWebSocketMessage> get messages => _messages.stream;

  @override
  Stream<void> get connections => _connections.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void retryNow() {}

  @override
  void send(String messageType, [Object? data]) {}

  @override
  void dispose() {
    _messages.close();
    _connections.close();
  }

  void push(ServerWebSocketMessage message) => _messages.add(message);
}

void main() {
  late _FakeSocket socket;
  late ProviderContainer container;

  setUp(() async {
    final client = _MockMediaServerClient();
    when(() => client.adminTasksApi).thenReturn(_FailingTasksApi());
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    socket = _FakeSocket();
    final handler = SocketHandler(clientFactory: (_) => socket)
      ..connectTo(client);
    container = ProviderContainer(
      overrides: [socketHandlerProvider.overrideWithValue(handler)],
    );
    addTearDown(() {
      container.dispose();
      handler.dispose();
    });
  });

  tearDown(() => GetIt.instance.reset());

  test('a push after a failed first load replaces the error', () async {
    final sub = container.listen(adminTasksProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(container.read(adminTasksProvider).hasError, isTrue);

    socket.push(const ScheduledTasksInfoMessage([
      {'Id': 'scan', 'Name': 'Scan Media Library', 'State': 'Running'},
    ]));
    await pumpEventQueue();

    final tasks = container.read(adminTasksProvider);
    expect(tasks.hasError, isFalse);
    expect(tasks.value?.single.id, 'scan');
  });
}
