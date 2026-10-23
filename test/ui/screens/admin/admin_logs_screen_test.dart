import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/logs/admin_logs_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves GET /System/Logs as Jellyfin 12.2 returns it.
class _FakeSystemApi extends Fake implements AdminSystemApi {
  int loads = 0;

  @override
  Future<List<LogFileInfo>> getLogFiles() async {
    loads++;
    return [
      LogFileInfo(
        name: 'log_20261001.log',
        size: 2048,
        dateCreated: DateTime.utc(2026, 10, 1),
        dateModified: DateTime.utc(2026, 10, 1, 12),
      ),
      LogFileInfo(
        name: 'log_20261002.log',
        size: 4096,
        dateCreated: DateTime.utc(2026, 10, 2),
        dateModified: DateTime.utc(2026, 10, 2, 12),
      ),
    ];
  }
}

void main() {
  late _FakeSystemApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminLogsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String name) =>
      tester.getTopLeft(find.text(name)).dy;

  testWidgets('newest first with the live badge, and the order flips', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.adminLogsTitle), findsOneWidget);
    expect(
      top(tester, 'log_20261002.log'),
      lessThan(top(tester, 'log_20261001.log')),
    );
    expect(find.text(l10n.liveBadge), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.adminLogsNewestFirst));
    await tester.pumpAndSettle();
    expect(
      top(tester, 'log_20261001.log'),
      lessThan(top(tester, 'log_20261002.log')),
    );
    expect(find.text(l10n.liveBadge), findsNothing);
  });

  testWidgets('refresh reads the list again', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip(l10n.refresh));
    await tester.pumpAndSettle();
    expect(api.loads, 2);
  });
}
