import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/emby/admin_emby_backups_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

const _trialExpired =
    'Emby Backup trial has expired. Please purchase Emby Premiere at https://emby.media.';

DioException _httpError(int status, [Object? body]) {
  final request = RequestOptions(path: '/BackupRestore');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: status, data: body),
  );
}

/// Serves GET /BackupRestore/BackupInfo and records restores, like the
/// Backup & Restore plugin.
class _FakeEmbyAdminApi extends Fake implements EmbyAdminApi {
  Map<String, dynamic> info = const {
    'FullBackupInfo': {'CanRestore': false, 'IsFullBackup': false},
    'LightBackups': [],
  };
  Object? infoError;
  Object? restoreError;
  final restores = <(bool, String?)>[];

  @override
  Future<PremiereStatus> getPremiereStatus() async =>
      const PremiereStatus(isActive: true, hasKey: true);

  @override
  Future<Map<String, dynamic>> getBackupInfo() async {
    if (infoError case final error?) throw error;
    return info;
  }

  @override
  Future<void> restoreBackup({
    bool restoreServerId = false,
    String? lightBackupName,
  }) async {
    restores.add((restoreServerId, lightBackupName));
    if (restoreError case final error?) throw error;
  }
}

/// The plugin's hidden EmbyServerBackup task, which fails without Premiere.
class _FakeTasksApi extends Fake implements AdminTasksApi {
  Map<String, dynamic> task = {
    'Id': 'backup-task',
    'Key': 'EmbyServerBackup',
    'Name': 'Emby Server Backup',
    'State': 'Idle',
    'IsHidden': true,
  };
  final started = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getTasks({bool? isHidden}) async => [
    {'Id': 'scan', 'Key': 'RefreshLibrary', 'Name': 'Scan', 'State': 'Idle'},
    task,
  ];

  @override
  Future<Map<String, dynamic>> getTask(String taskId) async => task;

  @override
  Future<void> startTask(String taskId) async {
    started.add(taskId);
    task = {
      ...task,
      'LastExecutionResult': {
        'StartTimeUtc': '2026-10-17T15:29:45Z',
        'EndTimeUtc': '2026-10-17T15:29:45Z',
        'Status': 'Failed',
        'ErrorMessage': _trialExpired,
      },
    };
  }
}

void main() {
  late _FakeEmbyAdminApi api;
  late _FakeTasksApi tasks;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeEmbyAdminApi();
    tasks = _FakeTasksApi();
    final client = _MockMediaServerClient();
    when(() => client.embyAdminApi).thenReturn(api);
    when(() => client.adminTasksApi).thenReturn(tasks);
    when(() => client.baseUrl).thenReturn('http://emby.test/emby');
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AdminServerScope(
            serverType: ServerType.emby,
            child: Scaffold(body: AdminEmbyBackupsScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const lightName = 'library.db-20261016';
  void withBackups() => api.info = const {
    'FullBackupInfo': {
      'CanRestore': true,
      'IsFullBackup': true,
      'DateCreated': '2026-10-17T03:10:00Z',
      'ServerVersion': '4.10.1.0',
      'PluginVersion': '1.8.7.0',
      'Users': [],
    },
    'LightBackups': [
      {'Name': lightName},
    ],
  };

  testWidgets('no backup yet means nothing to restore', (tester) async {
    await pump(tester);

    expect(find.text(l10n.adminNoBackups), findsOneWidget);
    expect(find.text(l10n.restore), findsNothing);
    expect(find.text(l10n.adminEmbyBackupNow), findsOneWidget);
  });

  testWidgets('the full backup and the database backups by name', (
    tester,
  ) async {
    withBackups();
    await pump(tester);

    expect(
      find.text(l10n.adminEmbyBackupServerVersion('4.10.1.0')),
      findsOneWidget,
    );
    expect(find.text(lightName), findsOneWidget);
    expect(find.text(l10n.restore), findsNWidgets(2));
  });

  testWidgets('restore asks first and sends the backup and server id choice', (
    tester,
  ) async {
    withBackups();
    await pump(tester);

    await tester.tap(find.text(l10n.restore).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminEmbyRestoreConfirm(lightName)), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(api.restores, isEmpty);

    await tester.tap(find.text(l10n.restore).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminEmbyRestoreServerId));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.restore));
    await tester.pumpAndSettle();
    expect(api.restores, [(false, lightName)]);
    expect(find.text(l10n.adminEmbyRestoreShuttingDown), findsOneWidget);
  });

  testWidgets('the full backup restores with the server id by default', (
    tester,
  ) async {
    withBackups();
    await pump(tester);

    await tester.tap(find.text(l10n.restore).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.restore));
    await tester.pumpAndSettle();
    expect(api.restores, [(true, null)]);
  });

  testWidgets('a refused restore shows the server\'s message', (tester) async {
    withBackups();
    api.restoreError = _httpError(500, _trialExpired);
    await pump(tester);

    await tester.tap(find.text(l10n.restore).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.restore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminRestoreFailed(_trialExpired)), findsOneWidget);
    expect(find.text(l10n.adminEmbyRestoreShuttingDown), findsNothing);
  });

  testWidgets('Back up now runs the backup task and shows why it failed', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminEmbyBackupNow));
    await tester.pump();
    expect(tasks.started, ['backup-task']);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.adminBackupCreateFailed(_trialExpired)),
      findsOneWidget,
    );
  });

  testWidgets('without the plugin it says so', (tester) async {
    api.infoError = _httpError(404);
    await pump(tester);

    expect(find.text(l10n.adminEmbyBackupsNoPlugin), findsOneWidget);
    expect(find.text(l10n.adminEmbyBackupNow), findsNothing);
  });

  testWidgets('another failure offers a retry', (tester) async {
    api.infoError = _httpError(500, 'Database is locked');
    await pump(tester);

    expect(find.text('Database is locked'), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
  });
}
