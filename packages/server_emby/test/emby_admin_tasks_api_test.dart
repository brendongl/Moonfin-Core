import 'package:server_emby/src/api/emby_admin_tasks_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  test('task routes', () async {
    final fake = AdminFake({'/ScheduledTasks': <dynamic>[]});
    final api = EmbyAdminTasksApi(fake.dio);

    await api.getTasks(isHidden: false);
    await api.getTask('t1');
    await api.startTask('t1');
    await api.stopTask('t1');
    await api.updateTaskTriggers('t1', [
      {'Type': 'IntervalTrigger', 'IntervalTicks': 1},
    ]);

    expect(
      [for (final r in fake.requests) '${r.method} ${r.path}'],
      [
        'GET /ScheduledTasks',
        'GET /ScheduledTasks/t1',
        'POST /ScheduledTasks/Running/t1',
        'DELETE /ScheduledTasks/Running/t1',
        'POST /ScheduledTasks/t1/Triggers',
      ],
    );
    expect(fake.requests.first.queryParameters, {'IsHidden': false});
    expect(fake.last.data, hasLength(1));
  });
}
