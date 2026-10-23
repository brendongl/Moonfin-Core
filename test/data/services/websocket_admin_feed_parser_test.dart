import 'package:flutter_test/flutter_test.dart';
import 'package:server_core/server_core.dart';

import 'package:moonfin/data/services/websocket_message_parser.dart';

void main() {
  test('a Sessions push carries the whole session list', () {
    final message = WebSocketMessageParser.parseJson({
      'MessageType': 'Sessions',
      'Data': [
        {'Id': 's1', 'DeviceId': 'tv'},
        {'Id': 's2', 'DeviceId': 'phone'},
      ],
    });

    expect(message, isA<SessionsMessage>());
    expect((message! as SessionsMessage).sessions.map((s) => s['Id']), [
      's1',
      's2',
    ]);
  });

  test('a ScheduledTasksInfo push carries the task list', () {
    final message = WebSocketMessageParser.parseJson({
      'MessageType': 'ScheduledTasksInfo',
      'Data': [
        {'Id': 't1', 'State': 'Running', 'CurrentProgressPercentage': 42.0},
      ],
    });

    expect(message, isA<ScheduledTasksInfoMessage>());
    expect((message! as ScheduledTasksInfoMessage).tasks.single['State'],
        'Running');
  });

  // The *Start names only ever travel from the client to the server.
  test('subscription names are not read as server messages', () {
    for (final type in ['SessionsStart', 'ScheduledTasksInfoStart']) {
      expect(
        WebSocketMessageParser.parseJson({'MessageType': type, 'Data': '0,1000'}),
        isNull,
      );
    }
  });

  test('server events Jellyfin does send come through', () {
    for (final type in [
      'RestartRequired',
      'PackageUninstalled',
      'PackageInstallationCancelled',
    ]) {
      final message = WebSocketMessageParser.parseJson({'MessageType': type});
      expect(message, isA<ServerEventMessage>(), reason: type);
    }
  });
}
