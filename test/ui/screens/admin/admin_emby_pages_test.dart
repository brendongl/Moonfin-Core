import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/admin_search_index.dart';
import 'package:moonfin/ui/screens/admin/emby/admin_sync_jobs_list.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_streaming_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> server = {
    'RemoteClientBitrateLimit': 0,
    'SimultaneousStreamLimit': 0,
  };
  final posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async =>
      Map<String, dynamic>.from(server);

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
    posted.add(config);
    server = Map<String, dynamic>.from(config);
  }
}

class _FakeEmbyApi extends Fake implements EmbyAdminApi {
  final conversions = <Map<String, dynamic>>[
    {
      'Id': '7',
      'Name': 'Movies',
      'TargetName': 'Living room',
      'Status': 'Converting',
      'Progress': 40.0,
      'ItemCount': 3,
    },
  ];
  final cancelled = <String>[];

  @override
  Future<PremiereStatus> getPremiereStatus() async =>
      const PremiereStatus(isActive: false, hasKey: false);

  @override
  Future<List<Map<String, dynamic>>> getSyncJobs({
    required bool conversions,
  }) async => conversions ? [...this.conversions] : [];

  @override
  Future<void> cancelSyncJob(String jobId) async {
    cancelled.add(jobId);
    conversions.removeWhere((j) => j['Id'] == jobId);
  }
}

void main() {
  late _FakeSystemApi api;
  late _FakeEmbyApi emby;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    emby = _FakeEmbyApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    when(() => client.embyAdminApi).thenReturn(emby);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AdminServerScope(
              serverType: ServerType.emby,
              child: SingleChildScrollView(child: page),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Emby streaming adds the stream limit with a Premiere note', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(height: 1500, child: AdminStreamingScreen()),
    );
    expect(find.text(l10n.adminStreamingStreamLimit), findsOneWidget);
    expect(find.text(l10n.adminPremiereNote), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, '3');
    await tester.pump();
    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.posted.single['SimultaneousStreamLimit'], 3);
    expect(api.posted.single['RemoteClientBitrateLimit'], 0);
  });

  testWidgets('conversion jobs list and cancel', (tester) async {
    await pump(tester, const AdminSyncJobsList());
    expect(find.text('Movies'), findsOneWidget);
    expect(
      find.text(
        'Living room · ${l10n.adminSyncJobConverting} · '
        '${l10n.adminSyncJobItemCount(3)}',
      ),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(l10n.adminSyncJobsEmpty), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.adminSyncJobCancel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminSyncJobCancel).last);
    await tester.pumpAndSettle();

    expect(emby.cancelled, ['7']);
    expect(find.text('Movies'), findsNothing);
    expect(find.text(l10n.adminSyncJobsEmpty), findsNWidgets(2));
  });

  test('the Emby page rows only show up in an Emby search', () {
    Set<String?> anchors(ServerType server) => {
      for (final entry in adminSearchEntries(server)) entry.anchor,
    };
    const embyRows = {
      'transcoding.HardwareAccelerationMode',
      'networking.WanDdns',
      'streaming.SimultaneousStreamLimit',
      'conversions.TemporaryPath',
    };
    const jellyfinRows = {'transcoding.EncoderPreset', 'networking.BaseUrl'};

    final emby = anchors(ServerType.emby);
    expect(emby, containsAll(embyRows));
    expect(emby.intersection(jellyfinRows), isEmpty);
    expect(emby, contains('streaming.RemoteClientBitrateLimit'));

    final jellyfin = anchors(ServerType.jellyfin);
    expect(jellyfin, containsAll(jellyfinRows));
    expect(jellyfin.intersection(embyRows), isEmpty);
  });
}
