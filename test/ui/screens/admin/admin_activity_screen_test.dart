import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/activity/admin_activity_screen.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves 30 activity entries in pages of the requested size and records the
/// filters of every request.
class _FakeAdminSystemApi extends Fake implements AdminSystemApi {
  final calls = <Map<String, Object?>>[];

  @override
  Future<ActivityLogResult> getActivityLog({
    int? startIndex,
    int? limit,
    bool? hasUserId,
    DateTime? minDate,
    DateTime? maxDate,
    String? severity,
    String? username,
  }) async {
    calls.add({
      'startIndex': startIndex,
      'limit': limit,
      'hasUserId': hasUserId,
      'minDate': minDate,
      'maxDate': maxDate,
      'severity': severity,
      'username': username,
    });
    const total = 30;
    final start = startIndex ?? 0;
    final count = (total - start).clamp(0, limit ?? total);
    return ActivityLogResult(
      items: [
        for (var i = start; i < start + count; i++)
          ActivityLogEntry(
            id: '$i',
            name: 'Entry $i',
            type: 'SessionStarted',
            date: DateTime.now().subtract(Duration(minutes: i)),
            userId: 'u1',
            itemId: i == 0 ? 'item0' : null,
          ),
      ],
      totalRecordCount: total,
    );
  }
}

class _FakeUsersApi extends Fake implements AdminUsersApi {
  @override
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden}) async =>
      const [ServerUser(id: 'u1', name: 'Axl')];
}

void main() {
  late _FakeAdminSystemApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeAdminSystemApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    when(() => client.adminUsersApi).thenReturn(_FakeUsersApi());
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

  Future<void> pump(
    WidgetTester tester, {
    bool? userActivity,
    Size size = const Size(1000, 800),
  }) async {
    // Short enough that 25 rows scroll, so the next page can load.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdminActivityScreen(userActivity: userActivity)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loads 25 a page in the view it is opened with', (tester) async {
    await pump(tester, userActivity: false);

    expect(api.calls.single, containsPair('hasUserId', false));
    expect(api.calls.single, containsPair('limit', 25));
    expect(api.calls.single, containsPair('startIndex', 0));
    // The System view has no user filter.
    expect(find.text(l10n.adminActivityAllUsers), findsNothing);
  });

  testWidgets('every level is offered and goes to the server', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminActivitySeverityAll));
    await tester.pumpAndSettle();
    // Only Information rows are loaded, the list still has every level.
    for (final level in [
      l10n.adminLogLevelTrace,
      l10n.adminLogLevelDebug,
      l10n.adminLogLevelWarning,
      l10n.adminLogLevelError,
      l10n.adminLogLevelNone,
    ]) {
      expect(find.text(level), findsOneWidget);
    }
    await tester.tap(find.text(l10n.adminLogLevelCritical));
    await tester.pumpAndSettle();

    expect(api.calls.last, containsPair('severity', 'Critical'));
    expect(api.calls.last, containsPair('startIndex', 0));
  });

  testWidgets('paging keeps the server filters', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.adminActivitySeverityAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminLogLevelError));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(api.calls.last, containsPair('startIndex', 25));
    expect(api.calls.last, containsPair('severity', 'Error'));
  });

  testWidgets('a user filters by username and names show on rows', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Axl'), findsWidgets);

    await tester.tap(find.text(l10n.adminActivityAllUsers));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Axl').last);
    await tester.pumpAndSettle();

    expect(api.calls.last, containsPair('username', 'Axl'));
    expect(api.calls.last, containsPair('startIndex', 0));
  });

  testWidgets('a date range goes to the server as whole days', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminActivityDateRange));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '10/01/2026');
    await tester.enterText(fields.at(1), '10/05/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(api.calls.last['minDate'], DateTime(2026, 10, 1));
    expect(api.calls.last['maxDate'], DateTime(2026, 10, 5, 23, 59, 59));
    expect(api.calls.last, containsPair('startIndex', 0));
  });

  // A window tall enough for the whole first page never scrolls, which left
  // the list stuck on its loader.
  testWidgets('a tall window still loads the next page', (tester) async {
    await pump(tester, size: const Size(1000, 4000));
    await tester.pumpAndSettle();

    expect(api.calls.map((c) => c['startIndex']), [0, 25]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an entry about an item offers its media details', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Entry 0'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminActivityMediaDetails), findsOneWidget);
    await tester.tap(find.text(l10n.close));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entry 1'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminActivityMediaDetails), findsNothing);
  });
}
