import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/backups/admin_backups_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

DioException _status(String path, int code) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: code),
    type: DioExceptionType.badResponse,
  );
}

/// Serves GET /Backup like Jellyfin 12.2, with no size, and records every
/// action.
class _FakeBackupApi extends Fake implements AdminBackupApi {
  List<Map<String, dynamic>> backups = [
    {
      'ServerVersion': '12.2.0',
      'BackupEngineVersion': '0.2.0',
      'DateCreated': '2026-09-01T10:00:00Z',
      'Path': '/config/data/backups/jellyfin-backup-20260901100000.zip',
      'Options': {'Metadata': false, 'Trickplay': false, 'Subtitles': false, 'Database': true},
    },
    {
      'ServerVersion': '12.2.0',
      'BackupEngineVersion': '0.2.0',
      'DateCreated': '2026-10-01T10:00:00Z',
      'Path': '/config/data/backups/jellyfin-backup-20261001100000.zip',
      'Options': {'Metadata': true, 'Trickplay': false, 'Subtitles': false, 'Database': true},
    },
  ];
  final created = <Map<String, dynamic>?>[];
  final restored = <String>[];
  Object? restoreError;

  @override
  Future<List<Map<String, dynamic>>> getBackups() async =>
      backups.map((b) => Map<String, dynamic>.from(b)).toList();

  @override
  Future<Map<String, dynamic>> createBackup([
    Map<String, dynamic>? options,
  ]) async {
    created.add(options);
    return const {};
  }

  @override
  Future<void> restoreBackup(String backupPath) async {
    restored.add(backupPath);
    if (restoreError != null) throw restoreError!;
  }
}

class _FakeTasksApi extends Fake implements AdminTasksApi {
  List<Map<String, dynamic>> tasks = [
    {'Name': 'Scan Media Library', 'State': 'Idle'},
  ];
  final calls = <bool?>[];

  @override
  Future<List<Map<String, dynamic>>> getTasks({bool? isHidden}) async {
    calls.add(isHidden);
    return tasks;
  }
}

/// Down for [downPolls] checks, then up.
class _FakeSystemApi extends Fake implements SystemApi {
  int downPolls = 1;
  int polls = 0;

  @override
  Future<Map<String, dynamic>> getPublicSystemInfo() async {
    polls++;
    if (polls <= downPolls) throw _status('/System/Info/Public', 503);
    return const {'Version': '12.2.0'};
  }
}

void main() {
  late _FakeBackupApi api;
  late _FakeTasksApi tasks;
  late _FakeSystemApi system;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeBackupApi();
    tasks = _FakeTasksApi();
    system = _FakeSystemApi();
    final client = _MockMediaServerClient();
    when(() => client.adminBackupApi).thenReturn(api);
    when(() => client.adminTasksApi).thenReturn(tasks);
    when(() => client.systemApi).thenReturn(system);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminBackupsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreate(WidgetTester tester) async {
    await tester.tap(find.text(l10n.adminCreateBackup));
    await tester.pumpAndSettle();
  }

  Future<void> confirmRestore(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.restore).last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(l10n.continueAction));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, l10n.restore));
    await tester.pump();
  }

  testWidgets('lists newest first by path, with no size', (tester) async {
    await pump(tester);

    final newer = find.text(api.backups[1]['Path'] as String);
    final older = find.text(api.backups[0]['Path'] as String);
    expect(tester.getTopLeft(newer).dy, lessThan(tester.getTopLeft(older).dy));
    // The server sends no size, so no row reads "date | 0 B".
    expect(find.textContaining(' | '), findsNothing);
  });

  testWidgets('create sends the options, all off by default', (tester) async {
    await pump(tester);
    await openCreate(tester);
    expect(find.text(l10n.adminBackupDisclaimer), findsOneWidget);

    await tester.tap(find.text(l10n.adminBackupSubtitles));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.create));
    await tester.pumpAndSettle();

    expect(tasks.calls, [false]);
    expect(api.created, [
      {'Metadata': false, 'Subtitles': true, 'Trickplay': false},
    ]);
    expect(find.text(l10n.adminBackupCreated), findsOneWidget);
  });

  testWidgets('running tasks ask before a backup', (tester) async {
    tasks.tasks = [
      {'Name': 'Scan Media Library', 'State': 'Running'},
      {'Name': 'Clean Cache Directory', 'State': 'Idle'},
    ];
    await pump(tester);

    await openCreate(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.create));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminBackupTasksWarningTitle), findsOneWidget);
    expect(find.text('- Scan Media Library'), findsOneWidget);
    expect(find.text('- Clean Cache Directory'), findsNothing);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(api.created, isEmpty);

    await openCreate(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.create));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.create));
    await tester.pumpAndSettle();
    expect(api.created, hasLength(1));
  });

  testWidgets('a restore 404 says the archive is missing', (tester) async {
    api.restoreError = _status('/Backup/Restore', 404);
    await pump(tester);

    await confirmRestore(tester);
    await tester.pumpAndSettle();

    expect(api.restored, [api.backups[1]['Path']]);
    expect(
      find.text(l10n.adminRestoreFailed(l10n.adminBackupArchiveNotFound)),
      findsOneWidget,
    );
    expect(find.textContaining(l10n.adminBackupsNotAvailable), findsNothing);
    expect(system.polls, 0);
  });

  testWidgets('a restore waits until the server answers again', (tester) async {
    await pump(tester);

    await confirmRestore(tester);
    await tester.pump();
    expect(find.text(l10n.adminRestoreInProgress), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(system.polls, 1);
    expect(find.text(l10n.adminRestoreInProgress), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(system.polls, 2);
    expect(find.text(l10n.adminRestoreInProgress), findsNothing);
    expect(find.text(l10n.adminRestoreSucceeded), findsOneWidget);
  });
}
