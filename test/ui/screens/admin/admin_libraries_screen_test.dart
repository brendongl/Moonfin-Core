import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/libraries/admin_libraries_screen.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_user_providers.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeLibraryApi extends Fake implements AdminLibraryApi {
  final calls = <String>[];

  @override
  Future<List<VirtualFolderInfo>> getVirtualFolders() async => const [
    VirtualFolderInfo(
      name: 'Movies',
      collectionType: 'movies',
      itemId: 'lib1',
      locations: ['/media/movies', '/media/more'],
    ),
  ];

  @override
  Future<void> refreshLibrary() async => calls.add('POST /Library/Refresh');
}

class _FakeTasksApi extends Fake implements AdminTasksApi {
  final started = <String>[];

  @override
  Future<void> startTask(String taskId) async => started.add(taskId);
}

class _FakeItemsApi extends Fake implements AdminItemsApi {
  final refreshes = <Map<String, Object?>>[];

  @override
  Future<void> refreshItem(
    String itemId, {
    bool? recursive,
    bool? replaceAllMetadata,
    bool? replaceAllImages,
    bool? regenerateTrickplay,
    MetadataRefreshMode metadataRefreshMode = MetadataRefreshMode.defaultRefresh,
    MetadataRefreshMode imageRefreshMode = MetadataRefreshMode.defaultRefresh,
  }) async {
    refreshes.add({
      'itemId': itemId,
      'Recursive': recursive,
      'MetadataRefreshMode': metadataRefreshMode.toServerString(),
      'ImageRefreshMode': imageRefreshMode.toServerString(),
      'ReplaceAllMetadata': replaceAllMetadata,
      'ReplaceAllImages': replaceAllImages,
      'RegenerateTrickplay': regenerateTrickplay,
    });
  }
}

void main() {
  late _FakeLibraryApi library;
  late _FakeTasksApi tasks;
  late _FakeItemsApi items;
  late AppLocalizations l10n;

  setUp(() async {
    library = _FakeLibraryApi();
    tasks = _FakeTasksApi();
    items = _FakeItemsApi();
    final client = _MockMediaServerClient();
    when(() => client.adminLibraryApi).thenReturn(library);
    when(() => client.adminTasksApi).thenReturn(tasks);
    when(() => client.adminItemsApi).thenReturn(items);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester, {String state = 'Idle'}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminTasksProvider.overrideWith(
            (ref) => Stream.value([
              TaskInfo(
                id: 'scan-task',
                key: 'RefreshLibrary',
                name: 'Scan Media Library',
                state: state,
                currentProgressPercentage: state == 'Running' ? 42 : null,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AdminLibrariesScreen()),
        ),
      ),
    );
    // The running scan shows a spinner that never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // POST /Library/Refresh cancels a running scan.
  testWidgets('scan all starts the RefreshLibrary task', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminRefreshAllLibraries));
    await tester.pump();

    expect(tasks.started, ['scan-task']);
    expect(library.calls, isEmpty);
  });

  testWidgets('scan all waits while the task runs', (tester) async {
    await pump(tester, state: 'Running');

    expect(find.text('${l10n.adminRefreshAllLibraries} 42%'), findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(
      find.widgetWithText(
          FloatingActionButton, '${l10n.adminRefreshAllLibraries} 42%'),
    );
    expect(fab.onPressed, isNull);
  });

  testWidgets('scan library offers the refresh modes', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminRefreshLibrary));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminReplaceImages), findsNothing);
    await tester.tap(find.text(l10n.adminRefreshModeScan));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminReplaceAllMetadata).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminReplaceTrickplayImages));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.refresh));
    await tester.pumpAndSettle();

    expect(items.refreshes.single, {
      'itemId': 'lib1',
      'Recursive': true,
      'MetadataRefreshMode': 'FullRefresh',
      'ImageRefreshMode': 'FullRefresh',
      'ReplaceAllMetadata': true,
      'ReplaceAllImages': false,
      'RegenerateTrickplay': true,
    });
  });

  testWidgets('remove lists the folders that go', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.delete));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminDeleteLibraryConfirm('Movies')), findsOneWidget);
    expect(find.text(l10n.adminDeleteLibraryLocations), findsOneWidget);
    expect(find.text('/media/more'), findsWidgets);
  });
}
