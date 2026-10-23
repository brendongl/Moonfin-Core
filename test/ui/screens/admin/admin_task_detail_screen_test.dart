import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/tasks/admin_task_detail_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

const _hour = 36000000000;

class _FakeTasksApi extends Fake implements AdminTasksApi {
  List<Map<String, dynamic>> triggers = [
    {'Type': 'DailyTrigger', 'TimeOfDayTicks': 0, 'MaxRuntimeTicks': 54000000000},
    {'Type': 'IntervalTrigger', 'IntervalTicks': 9000000000},
  ];
  final posted = <List<Map<String, dynamic>>>[];

  Map<String, dynamic> get _task => {
    'Id': 'scan',
    'Name': 'Scan Media Library',
    'Category': 'Library',
    'State': 'Idle',
    'Triggers': triggers,
  };

  @override
  Future<List<Map<String, dynamic>>> getTasks({bool? isHidden}) async => [_task];

  @override
  Future<Map<String, dynamic>> getTask(String taskId) async => _task;

  @override
  Future<void> updateTaskTriggers(
    String taskId,
    List<Map<String, dynamic>> triggers,
  ) async {
    posted.add(triggers);
    this.triggers = triggers;
  }
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
          home: const Scaffold(body: AdminTaskDetailScreen(taskId: 'scan')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('triggers show a locale time, fractional hours and minutes', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(l10n.adminTaskTriggerDaily('12:00 AM')), findsOneWidget);
    // 1.5 h stays fractional instead of rounding down to 1 hour.
    expect(
      find.text(l10n.adminTimeLimitDuration(l10n.adminTaskHoursValue('1.5'))),
      findsOneWidget,
    );
    expect(find.text(l10n.adminTaskTriggerEveryMinutes('15')), findsOneWidget);
  });

  testWidgets('removing a trigger asks first', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip(l10n.delete).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminDeleteTaskTriggerConfirm), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(api.posted, isEmpty);

    await tester.tap(find.byTooltip(l10n.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.delete));
    await tester.pumpAndSettle();
    expect(api.posted.single, [
      {'Type': 'IntervalTrigger', 'IntervalTicks': 9000000000},
    ]);
  });

  testWidgets('a new trigger defaults to daily at midnight', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminAddTrigger));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.adminTimeLimitHours),
      '1.5',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.add));
    await tester.pumpAndSettle();

    expect(api.posted.single.last, {
      'Type': 'DailyTrigger',
      'TimeOfDayTicks': 0,
      'MaxRuntimeTicks': (1.5 * _hour).round(),
    });
  });

  testWidgets('an interval trigger starts at 15 minutes', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminAddTrigger));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminTaskTriggerTypeDaily).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminTaskTriggerTypeInterval).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminTaskMinutesValue('15')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.add));
    await tester.pumpAndSettle();

    expect(api.posted.single.last, {
      'Type': 'IntervalTrigger',
      'IntervalTicks': 9000000000,
    });
  });

  testWidgets('an Emby system event trigger is read-only and kept', (
    tester,
  ) async {
    const event = {
      'Type': 'SystemEventTrigger',
      'SystemEvent': 'DisplayConfigurationChange',
    };
    api.triggers = [event, ...api.triggers];
    await pump(tester);

    expect(
      find.text(l10n.adminTaskTriggerSystemEvent('DisplayConfigurationChange')),
      findsOneWidget,
    );
    // Only the daily and interval triggers can be removed.
    expect(find.byTooltip(l10n.delete), findsNWidgets(2));

    await tester.tap(find.byTooltip(l10n.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.delete));
    await tester.pumpAndSettle();
    expect(api.posted.single, [
      event,
      {'Type': 'IntervalTrigger', 'IntervalTicks': 9000000000},
    ]);
  });

  testWidgets('a time limit under one hour can\'t be added', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminAddTrigger));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.adminTimeLimitHours),
      '0.5',
    );
    await tester.pump();

    final add = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.add),
    );
    expect(add.onPressed, isNull);
  });
}
