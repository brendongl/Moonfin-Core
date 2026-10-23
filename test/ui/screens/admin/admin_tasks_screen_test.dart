import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/tasks/admin_tasks_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeTasksApi extends Fake implements AdminTasksApi {
  final hiddenArgs = <bool?>[];
  final started = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getTasks({bool? isHidden}) async {
    hiddenArgs.add(isHidden);
    final end = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return [
      {
        'Id': 'scan',
        'Name': 'Scan Media Library',
        'Category': 'Library',
        'State': 'Idle',
        'LastExecutionResult': {
          'StartTimeUtc': end
              .subtract(const Duration(minutes: 2, seconds: 5))
              .toIso8601String(),
          'EndTimeUtc': end.toIso8601String(),
          'Status': 'Failed',
        },
      },
      // A task without a category is left out.
      {'Id': 'loose', 'Name': 'No category task', 'State': 'Idle'},
    ];
  }

  @override
  Future<void> startTask(String taskId) async => started.add(taskId);
}

void main() {
  late _FakeTasksApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeTasksApi();
    final client = _MockMediaServerClient();
    when(() => client.adminTasksApi).thenReturn(api);
    await GetIt.instance.reset();
    GetIt.instance
      ..registerSingleton<MediaServerClient>(client)
      ..registerSingleton<SocketHandler>(SocketHandler());
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AdminTasksScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists visible tasks with a localized last run', (tester) async {
    await pump(tester);

    expect(api.hiddenArgs, [false]);
    expect(find.text('Scan Media Library'), findsOneWidget);
    expect(find.text('No category task'), findsNothing);
    final lastRan = l10n.adminTaskLastRan(
      l10n.adminActivityHoursAgo(3),
      '${l10n.adminActivityMinutesShort(2)} ${l10n.adminDurationSecondsShort('5')}',
    );
    expect(
      find.text('$lastRan (${l10n.adminTaskResultFailed})'),
      findsOneWidget,
    );
  });

  testWidgets('run starts the task', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip(l10n.adminTaskRun));
    await tester.pumpAndSettle();
    expect(api.started, ['scan']);
  });
}
