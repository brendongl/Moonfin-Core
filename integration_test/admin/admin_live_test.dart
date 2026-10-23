// Opens every admin page against a real server and saves each settings page
// once through the UI, logging every request. Skips unless the server is
// configured:
//
//   MOONFIN_LIVE_URL=<server url> MOONFIN_LIVE_TOKEN=<admin token> \
//   MOONFIN_LIVE_USER_ID=<admin user id> \
//   dbus-run-session -- flutter test integration_test/admin -d linux
//
// MOONFIN_LIVE_SERVER_TYPE=emby runs it against Emby, whose URL ends in /emby.
// MOONFIN_LIVE_READONLY=1 only opens pages and refuses anything but a GET.
// MOONFIN_LIVE_PREMIERE=1 checks an Emby server with Premiere, and adding
// MOONFIN_LIVE_CHANNELS=1 turns its first channel off and moves it, then puts
// both back.
// The saves put back what they change, but run them on a disposable server.
// MOONFIN_LIVE_LOG names a file to write the request log to (JSON lines), and
// MOONFIN_LIVE_SHOTS names a folder to save a screenshot of each page in.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_analytics_items_screen.dart';
import 'package:moonfin/ui/screens/admin/admin_routes.dart';
import 'package:moonfin/ui/screens/admin/metadata/admin_metadata_edit_screen.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_media_analytics_provider.dart';
import 'package:moonfin/ui/screens/admin/widgets/admin_settings_search.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin_design/moonfin_design.dart' show ThemeRegistry;
import 'package:server_core/server_core.dart';
import 'package:server_emby/server_emby.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

class _Request {
  _Request(this.page, this.method, this.path, this.query, this.status);
  final String page;
  final String method;
  final String path;
  final Map<String, dynamic> query;
  int? status;

  Map<String, dynamic> toJson() => {
    'page': page,
    'method': method,
    'path': path,
    'query': query.map((k, v) => MapEntry(k, '$v')),
    'status': status,
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final url = env['MOONFIN_LIVE_URL'];
  final token = env['MOONFIN_LIVE_TOKEN'];
  final userId = env['MOONFIN_LIVE_USER_ID'];
  final isEmby = env['MOONFIN_LIVE_SERVER_TYPE'] == 'emby';
  final readOnly = env['MOONFIN_LIVE_READONLY'] == '1';
  final premiere = isEmby && env['MOONFIN_LIVE_PREMIERE'] == '1';
  final channelWrites = premiere && env['MOONFIN_LIVE_CHANNELS'] == '1';
  // Emby 4.9 has no RefreshGuide, so Emby uses a quick task both versions
  // have, which the feed test also starts.
  final quickTask = isEmby ? 'ScanInternalMetadataFolderTask' : 'RefreshGuide';
  final skip = url == null || token == null || userId == null
      ? 'set MOONFIN_LIVE_URL, MOONFIN_LIVE_TOKEN and MOONFIN_LIVE_USER_ID'
      : null;

  final log = <_Request>[];
  var currentPage = '';
  late MediaServerClient client;
  final ids = <String, String>{};

  setUpAll(() async {
    if (skip != null) return;
    // Logged paths leave out Emby's /emby prefix.
    final basePath = Uri.parse(url!).path;
    const deviceInfo = DeviceInfo(
      id: 'moonfin-admin-live-test',
      name: 'Admin live test',
      appName: 'Moonfin',
      appVersion: 'test',
    );
    final interceptors = [
      InterceptorsWrapper(
        onRequest: (o, h) {
          o.extra['_log'] = _Request(
            currentPage,
            o.method,
            o.uri.path.substring(basePath.length),
            {...o.uri.queryParameters}
              // Jellyfin's ApiKey and Emby's api_key.
              ..removeWhere(
                (k, _) =>
                    k.toLowerCase().replaceAll('_', '').contains('apikey'),
              ),
            null,
          );
          log.add(o.extra['_log'] as _Request);
          final channelChange = channelWrites &&
              o.uri.path.contains('/LiveTv/Manage/Channels/');
          if (readOnly && o.method != 'GET' && !channelChange) {
            return h.reject(DioException(requestOptions: o, error: 'read only'));
          }
          h.next(o);
        },
        onResponse: (r, h) {
          (r.requestOptions.extra['_log'] as _Request?)?.status = r.statusCode;
          h.next(r);
        },
        onError: (e, h) {
          (e.requestOptions.extra['_log'] as _Request?)?.status =
              e.response?.statusCode ?? -1;
          h.next(e);
        },
      ),
    ];
    client = isEmby
        ? EmbyMediaServerClient(
            baseUrl: url,
            deviceInfo: deviceInfo,
            interceptors: interceptors,
          )
        : JellyfinMediaServerClient(
            baseUrl: url,
            deviceInfo: deviceInfo,
            interceptors: interceptors,
          );
    client
      ..accessToken = token
      ..userId = userId;
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    final socket = SocketHandler()..connectTo(client);
    GetIt.instance.registerSingleton<SocketHandler>(socket);

    // Real ids for the pages that need one.
    final users = await client.adminUsersApi.getUsers();
    ids['user'] = users
        .firstWhere((u) => !(u.policy?.isAdministrator ?? false))
        .id;
    final libraries = await client.adminLibraryApi.getVirtualFolders();
    ids['library'] = libraries.firstWhere((l) => l.name == 'Movies').itemId;
    final tasks = await client.adminTasksApi.getTasks(isHidden: false);
    ids['task'] = tasks.firstWhere((t) => t['Key'] == quickTask)['Id'] as String;
    final plugins = await client.adminPluginsApi.getInstalledPlugins();
    ids['plugin'] = plugins.first.id;
    final logs = await client.adminSystemApi.getLogFiles();
    ids['log'] = logs.first.name;
    var items = await client.itemsApi.getItems(
      searchTerm: 'Big Buck Bunny',
      includeItemTypes: const ['Movie'],
      recursive: true,
    );
    if ((items['Items'] as List).isEmpty) {
      items = await client.itemsApi.getItems(
        includeItemTypes: const ['Movie'],
        recursive: true,
        limit: 1,
      );
    }
    ids['item'] = ((items['Items'] as List).first as Map)['Id'] as String;
  });

  tearDownAll(() async {
    if (skip != null) return;
    final out = env['MOONFIN_LIVE_LOG'];
    if (out != null) {
      File(out).writeAsStringSync(
        log.map((r) => jsonEncode(r.toJson())).join('\n'),
      );
    }
  });

  late AppLocalizations l10n;

  final shotKey = GlobalKey();

  Future<GoRouter> pumpAdmin(
    WidgetTester tester,
    String location, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: Destinations.home, builder: (_, _) => const SizedBox()),
        adminShellRoute,
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: RepaintBoundary(
          key: shotKey,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.buildTheme(ThemeRegistry.active),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      ),
    );
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    return router;
  }

  /// Saves the window as <MOONFIN_LIVE_SHOTS>/<name>.png for review, when set.
  Future<void> shot(String name) async {
    final dir = env['MOONFIN_LIVE_SHOTS'];
    if (dir == null) return;
    final boundary =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  }

  /// Real requests take real time, so pump until nothing is loading.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          i > 5) {
        return;
      }
    }
  }

  void expectNoFailures(String page) {
    final failed = log
        .where((r) => r.page == page && r.status != null && r.status! >= 400 ||
            r.page == page && r.status == -1)
        .map((r) => '${r.method} ${r.path} ${r.status}')
        .toList();
    expect(failed, isEmpty, reason: '$page made failing requests');
    // Still waiting when the test moved on (the plugin catalog comes from the
    // internet), so neither passed nor failed.
    final pending = log.where((r) => r.page == page && r.status == null);
    for (final r in pending) {
      debugPrint('PENDING $page ${r.method} ${r.path}');
    }
  }

  final pages = <String, String Function()>{
    'dashboard': () => Destinations.admin,
    'analytics': () => Destinations.adminAnalytics,
    'analytics-items': () => AdminAnalyticsQuery(
      libraryId: ids['library'],
      dimension: AdminAnalyticsDimension.type,
      values: const ['movies'],
      title: 'Movies',
    ).location,
    'activity': () => Destinations.adminActivity,
    'tasks': () => Destinations.adminTasks,
    'task-detail': () => Destinations.adminTask(ids['task']!),
    'libraries': () => Destinations.adminLibraries,
    'library-add': () => Destinations.adminLibrariesAdd,
    'library-edit': () => Destinations.adminLibrary(ids['library']!),
    if (!isEmby) 'display': () => Destinations.adminSettingsDisplay,
    'metadata': () => Destinations.adminSettingsMetadata,
    'nfo': () => Destinations.adminSettingsNfo,
    'metadata-edit': () => Destinations.adminMetadata(ids['item']!),
    'live-tv': () => Destinations.adminLiveTv,
    'transcoding': () => Destinations.adminSettingsPlayback,
    if (!isEmby) ...{
      'resume': () => Destinations.adminSettingsResume,
      'trickplay': () => Destinations.adminSettingsTrickplay,
      'repositories': () => Destinations.adminRepositories,
    },
    'streaming': () => Destinations.adminSettingsStreaming,
    'users': () => Destinations.adminUsers,
    'user-add': () => Destinations.adminUsersAdd,
    'user-edit': () => Destinations.adminUser(ids['user']!),
    'devices': () => Destinations.adminDevices,
    'api-keys': () => Destinations.adminKeys,
    'settings': () => Destinations.adminSettings,
    'branding': () => Destinations.adminSettingsBranding,
    'networking': () => Destinations.adminSettingsNetworking,
    'plugins': () => Destinations.adminPlugins,
    'plugin-detail': () => Destinations.adminPlugin(ids['plugin']!),
    'backups': () => Destinations.adminBackups,
    'logs': () => Destinations.adminLogs,
    'log-viewer': () => Destinations.adminLogFile(ids['log']!),
    if (isEmby) ...{
      'live-tv-channels': () => Destinations.adminLiveTvChannels,
      'premiere': () => Destinations.adminPremiere,
      'database': () => Destinations.adminDatabase,
      'cinema-intros': () => Destinations.adminCinemaIntros,
      'dlna': () => Destinations.adminDlna,
      'camera-upload': () => Destinations.adminCameraUpload,
      'conversions': () => Destinations.adminConversions,
    },
    for (final g in ['overview', 'library', 'playback', 'people', 'system'])
      'group-$g': () => Destinations.adminGroupPath(g),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key} opens with live data', skip: skip != null, (
      tester,
    ) async {
      currentPage = entry.key;
      await pumpAdmin(tester, entry.value());
      await settle(tester);
      // The plugin pages wait on the online catalog.
      if (entry.key.startsWith('plugin')) {
        await tester.pump(const Duration(seconds: 10));
        await settle(tester);
      }

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.adminSettingsLoadFailed), findsNothing);
      expectNoFailures(entry.key);
      await shot('desktop-${entry.key}');
      AdminDraft.active.value = null;
    });
  }

  // The phone layout: group tabs along the bottom, a page list per group.
  for (final key in [
    'dashboard',
    'analytics',
    'analytics-items',
    for (final g in ['overview', 'library', 'playback', 'people', 'system'])
      'group-$g',
    'settings',
    'live-tv',
    'user-edit',
    'library-edit',
    'metadata-edit',
  ]) {
    testWidgets('$key opens on a phone', skip: skip != null, (tester) async {
      currentPage = '$key:phone';
      await pumpAdmin(tester, pages[key]!(), size: const Size(390, 844));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text(l10n.adminSettingsLoadFailed), findsNothing);
      expectNoFailures(currentPage);
      await shot('phone-$key');
      AdminDraft.active.value = null;
    });
  }

  // Categories open their items over the page and the items open the editor
  // over that, each with a back arrow to the one before.
  testWidgets('a tapped codec lists its items with a way back',
      skip: skip != null, (tester) async {
    currentPage = 'analytics:drill';
    await pumpAdmin(tester, Destinations.adminAnalytics);
    await settle(tester);
    final codec = find.text('H.264').first;
    await tester.ensureVisible(codec);
    await tester.tap(codec);
    await settle(tester);
    expect(find.byType(AdminAnalyticsItemsScreen), findsOneWidget);
    final back = find.byTooltip(
      MaterialLocalizations.of(
        tester.element(find.byType(AdminAnalyticsItemsScreen)),
      ).backButtonTooltip,
    );
    expect(back, findsOneWidget);
    await shot('desktop-analytics-drill');

    await tester.tap(
      find
          .descendant(
            of: find.byType(AdminAnalyticsItemsScreen),
            matching: find.byIcon(Icons.chevron_right),
          )
          .first,
    );
    await settle(tester);
    expect(find.byType(AdminMetadataEditScreen), findsOneWidget);
    await tester.tap(back);
    await settle(tester);
    expect(find.byType(AdminAnalyticsItemsScreen), findsOneWidget);
    await tester.tap(back);
    await settle(tester);
    expect(find.byType(AdminAnalyticsItemsScreen), findsNothing);
    expect(back, findsNothing);
    expect(tester.takeException(), isNull);
    expectNoFailures(currentPage);
    AdminDraft.active.value = null;
  });

  // The dashboard subscribes to sessions and scheduled tasks, but the server
  // pushes only on events, so a capabilities report and a quick task stand in
  // for a client starting up and a task running.
  testWidgets('the dashboard gets pushed sessions and tasks',
      skip: skip != null || readOnly, (
    tester,
  ) async {
    currentPage = 'dashboard:feeds';
    final pushed = <Type>{};
    final sub = GetIt.instance<SocketHandler>().events.listen(
      (e) => pushed.add(e.runtimeType),
    );
    addTearDown(sub.cancel);
    await pumpAdmin(tester, Destinations.admin);
    await settle(tester);
    await client.sessionApi.reportCapabilities({
      'PlayableMediaTypes': ['Video'],
      'SupportedCommands': <String>[],
      'SupportsMediaControl': false,
    });
    final tasks = await client.adminTasksApi.getTasks(isHidden: false);
    await client.adminTasksApi.startTask(
      tasks.firstWhere(
            (t) => t['Key'] == (isEmby ? quickTask : 'DeleteTranscodeFiles'),
          )['Id']
          as String,
    );
    const feeds = [SessionsMessage, ScheduledTasksInfoMessage];
    for (var i = 0; i < 150 && !pushed.containsAll(feeds); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(pushed, containsAll(feeds));
    AdminDraft.active.value = null;
  });

  // Each settings page saves once through the bar: flip its first switch (or
  // edit its first text field), save, check the post went through, then put
  // it back and save again.
  final draftPages = {
    // Emby's first switch is maintenance mode, so it edits a text field.
    'settings': _Save('POST', '/System/Configuration', text: isEmby),
    'metadata': const _Save('POST', '/System/Configuration'),
    'nfo': const _Save('POST', '/System/Configuration/xbmcmetadata'),
    'transcoding': const _Save('POST', '/System/Configuration/encoding'),
    'streaming': const _Save('POST', '/System/Configuration', text: true),
    if (isEmby) ...{
      'database': const _Save('POST', '/System/Configuration'),
      'cinema-intros': const _Save('POST', '/System/Configuration/cinemamode'),
      'dlna': const _Save('POST', '/System/Configuration/dlna'),
      'camera-upload': const _Save('POST', '/System/Configuration/devices'),
      'conversions': const _Save('POST', '/System/Configuration/sync'),
    } else ...{
      'display': const _Save('POST', '/System/Configuration'),
      'resume': const _Save('POST', '/System/Configuration'),
      'trickplay': const _Save('POST', '/System/Configuration'),
    },
    // Branding's first switch (the splash screen) saves at once and stays out
    // of the draft, so this edits a text field.
    'branding': const _Save('POST', '/System/Configuration/branding', text: true),
    'networking': _Save(
      'POST',
      isEmby ? '/System/Configuration' : '/System/Configuration/network',
    ),
    // The server refuses a recording path that doesn't exist.
    'live-tv': _Save(
      'POST',
      '/System/Configuration/livetv',
      tab: (l) => l.adminLiveTvTabRecordings,
      anchor: 'live-tv.RecordingPostProcessorArguments',
    ),
    'library-edit': _Save(
      'POST',
      '/Library/VirtualFolders/LibraryOptions',
      tab: (l) => l.adminLibraryTabOptions,
    ),
    'metadata-edit': const _Save('POST', '/Items/{item}', text: true),
    'user-edit': _Save('POST', isEmby ? '/Users/{user}' : '/Users', text: true),
    'user-policy': _Save(
      'POST',
      '/Users/{user}/Policy',
      page: 'user-edit',
      tab: (l) => l.permissions,
    ),
  };

  // IndexedStack keeps every tab built, so only the shown one counts.
  bool onShownTab(Element e) {
    var shown = true;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Visibility && !w.visible) shown = false;
      return shown;
    });
    return shown;
  }

  for (final entry in draftPages.entries) {
    testWidgets('${entry.key} saves through the bar',
        skip: skip != null || readOnly, (
      tester,
    ) async {
      final spec = entry.value;
      currentPage = '${entry.key}:save';
      await pumpAdmin(tester, pages[spec.page ?? entry.key]!());
      await settle(tester);
      if (spec.tab != null) {
        await tester.tap(find.text(spec.tab!(l10n)));
        await settle(tester);
      }
      final anchor = find.byWidgetPredicate(
        (w) => w is AdminSettingAnchor && w.id == spec.anchor,
      );

      String? original;
      Future<void> changeAndSave({required bool restore}) async {
        Iterable<Element> shown(Type kind) => (spec.anchor == null
                ? find.byType(kind)
                : find.descendant(of: anchor, matching: find.byType(kind)))
            .evaluate()
            .where(onShownTab);
        // Pages without a switch edit their first text field.
        final switches = spec.text ? const <Element>[] : shown(Switch);
        final kind = switches.isEmpty ? TextFormField : Switch;
        final control =
            (switches.isEmpty ? shown(TextFormField) : switches).first.widget;
        final target = find.byWidget(control);
        await tester.ensureVisible(target);
        if (kind == Switch) {
          await tester.tap(target);
        } else {
          final text = tester
              .widget<TextField>(
                find.descendant(of: target, matching: find.byType(TextField)),
              )
              .controller!
              .text;
          original ??= text;
          await tester.enterText(target, restore ? original! : '${text}1');
        }
        await tester.pump();
        expect(AdminDraft.active.value?.isDirty, isTrue);
        // The bar slides in and the last save's snackbar slides out. This
        // binding only draws frames when the test pumps, so pump several.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final save = find.widgetWithText(FilledButton, l10n.save);
        await tester.tap(save);
        await settle(tester);
        expect(AdminDraft.active.value?.isDirty, isFalse);
      }

      final before = log.length;
      await changeAndSave(restore: false);
      final method = spec.method;
      final path = spec.path.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) => ids[m[1]]!,
      );
      expect(
        log.skip(before).where(
          (r) =>
              r.method == method &&
              r.path == path &&
              (r.status == 204 || r.status == 200),
        ),
        isNotEmpty,
        reason: '${entry.key} should $method $path',
      );
      // Put the server back as it was.
      await changeAndSave(restore: true);
      expectNoFailures(currentPage);
      AdminDraft.active.value = null;
    });
  }

  testWidgets('a licensed server shows no Premiere notes',
      skip: skip != null || !premiere, (tester) async {
    currentPage = 'premiere:licensed';
    final router = await pumpAdmin(tester, Destinations.adminPremiere);
    await settle(tester);
    expect(find.text(l10n.adminPremiereActive), findsOneWidget);
    for (final route in [
      Destinations.adminSettingsPlayback,
      Destinations.adminSettingsStreaming,
      Destinations.adminLiveTv,
      Destinations.adminLiveTvChannels,
      Destinations.adminCinemaIntros,
      Destinations.adminConversions,
    ]) {
      router.go(route);
      await settle(tester);
      expect(find.text(l10n.adminPremiereNote), findsNothing, reason: route);
      expect(
        find.text(l10n.adminPremiereNoteLiveTv),
        findsNothing,
        reason: route,
      );
    }
    expectNoFailures(currentPage);
    AdminDraft.active.value = null;
  });

  // Only reads: the dialog closes without mapping anything.
  testWidgets('the mapping dialog shows the current mappings',
      skip: skip != null || !premiere, (tester) async {
    currentPage = 'live-tv:mappings';
    final channels = await client.embyAdminApi!.getManagedChannels(limit: 1);
    final first = (channels['Items'] as List).first as Map;
    await pumpAdmin(tester, Destinations.adminLiveTv);
    await settle(tester);
    await tester.tap(find.byTooltip(l10n.adminLiveTvMapChannels).first);
    await settle(tester);
    expect(find.text('${first['ListingsChannelName']}'), findsWidgets);
    await tester.tap(find.text(l10n.close).last);
    await settle(tester);
    expectNoFailures(currentPage);
  });

  testWidgets('a channel turns off and moves, then goes back',
      skip: skip != null || !channelWrites, (tester) async {
    currentPage = 'live-tv-channels:changes';
    final emby = client.embyAdminApi!;
    Future<List<Map>> firstTwo() async =>
        ((await emby.getManagedChannels(limit: 2))['Items'] as List).cast<Map>();
    // Turning a channel back on gives it a new item id, so channels are told
    // apart by ManagementId.
    final [a, b] = await firstTwo();
    final wasDisabled = a['Disabled'] == true;
    List<Object?> order(List<Map> channels) =>
        [for (final c in channels) c['ManagementId']];
    // Put the server back even when a step fails.
    addTearDown(() async {
      final [now, next] = await firstTwo();
      final current = now['ManagementId'] == a['ManagementId'] ? now : next;
      if ((current['Disabled'] == true) != wasDisabled) {
        await emby.setChannelDisabled(
          '${current['Id']}',
          managementId: '${a['ManagementId']}',
          disabled: wasDisabled,
        );
      }
      if (now['ManagementId'] != a['ManagementId']) {
        await emby.setChannelSortIndex(
          '${current['Id']}',
          managementId: '${a['ManagementId']}',
          newIndex: 0,
        );
      }
    });
    await pumpAdmin(tester, Destinations.adminLiveTvChannels);
    await settle(tester);

    final toggle = find.byType(Switch).first;
    await tester.tap(toggle);
    await settle(tester);
    expect((await firstTwo()).first['Disabled'] == true, !wasDisabled);
    await tester.tap(toggle);
    await settle(tester);
    expect((await firstTwo()).first['Disabled'] == true, wasDisabled);

    await tester.tap(find.byTooltip(l10n.moveDown).first);
    await settle(tester);
    expect(order(await firstTwo()), order([b, a]));
    await tester.tap(find.byTooltip(l10n.moveUp).at(1));
    await settle(tester);
    expect(order(await firstTwo()), order([a, b]));
    expectNoFailures(currentPage);
  });
}

/// One page's save check. [tab] opens that tab first, [anchor] picks the
/// search anchor whose field gets edited, and `{id}` names in [path] are
/// filled from the test's ids.
class _Save {
  const _Save(
    this.method,
    this.path, {
    this.page,
    this.tab,
    this.anchor,
    this.text = false,
  });

  final String method;
  final String path;
  final String? page;
  final String Function(AppLocalizations)? tab;
  final String? anchor;
  final bool text;
}
