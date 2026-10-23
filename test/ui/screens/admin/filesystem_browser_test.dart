import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/widgets/filesystem_browser.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeEnvironmentApi extends Fake implements AdminEnvironmentApi {
  final validated = <(String, bool?)>[];

  @override
  Future<List<Map<String, dynamic>>> getDrives() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getDirectoryContents(
    String path, {
    bool? includeFiles,
    bool? includeDirectories,
  }) async => [
    {'Name': 'cert.pfx', 'Path': '$path/cert.pfx', 'Type': 'File'},
  ];

  @override
  Future<String?> getParentPath(String path) async => null;

  @override
  Future<void> validatePath(
    String path, {
    bool writable = false,
    bool? isFile,
  }) async {
    validated.add((path, isFile));
  }
}

void main() {
  late _FakeEnvironmentApi env;
  late AppLocalizations l10n;

  setUp(() async {
    env = _FakeEnvironmentApi();
    final client = _MockMediaServerClient();
    when(() => client.adminEnvironmentApi).thenReturn(env);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<List<String>> pump(WidgetTester tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FilesystemBrowser(
            initialPath: '/config',
            includeFiles: true,
            onPathSelected: picked.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  // A typed path can be a file, and IsFile false would make the server
  // insist on a folder.
  testWidgets('a typed path is checked as a file or a folder', (tester) async {
    final picked = await pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.path),
      '/config/ssl/cert.pfx',
    );
    await tester.tap(find.text(l10n.select));
    await tester.pumpAndSettle();

    expect(env.validated, [('/config/ssl/cert.pfx', null)]);
    expect(picked, ['/config/ssl/cert.pfx']);
  });

  testWidgets('a tapped file is checked as a file', (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.text('cert.pfx'));
    await tester.pumpAndSettle();

    expect(env.validated, [('/config/cert.pfx', true)]);
    expect(picked, ['/config/cert.pfx']);
  });
}
