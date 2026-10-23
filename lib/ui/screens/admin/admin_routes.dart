import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/destinations.dart';
import 'activity/admin_activity_screen.dart';
import 'admin_analytics_items_screen.dart';
import 'admin_content_analytics_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_draft.dart';
import 'admin_group_index_screen.dart';
import 'admin_nav.dart';
import 'admin_shell_screen.dart';
import 'backups/admin_backups_screen.dart';
import 'devices/admin_devices_screen.dart';
import 'emby/admin_config_form.dart';
import 'emby/admin_emby_backups_screen.dart';
import 'emby/admin_emby_transcoding_screen.dart';
import 'emby/admin_live_tv_channels_screen.dart';
import 'emby/admin_premiere_screen.dart';
import 'emby/admin_sync_jobs_list.dart';
import 'emby/emby_config_pages.dart';
import 'keys/admin_api_keys_screen.dart';
import 'libraries/admin_libraries_screen.dart';
import 'libraries/admin_library_add_screen.dart';
import 'libraries/admin_library_display_screen.dart';
import 'libraries/admin_library_edit_screen.dart';
import 'libraries/admin_library_metadata_screen.dart';
import 'libraries/admin_library_nfo_screen.dart';
import 'livetv/admin_live_tv_screen.dart';
import 'logs/admin_log_viewer_screen.dart';
import 'logs/admin_logs_screen.dart';
import 'metadata/admin_metadata_edit_screen.dart';
import 'plugins/admin_plugin_detail_screen.dart';
import 'plugins/admin_plugins_screen.dart';
import 'plugins/admin_repositories_screen.dart';
import 'providers/admin_media_analytics_provider.dart';
import 'settings/admin_branding_screen.dart';
import 'settings/admin_general_settings_screen.dart';
import 'settings/admin_networking_screen.dart';
import 'settings/admin_playback_settings_screen.dart';
import 'settings/admin_resume_settings_screen.dart';
import 'settings/admin_streaming_screen.dart';
import 'settings/admin_trickplay_screen.dart';
import 'tasks/admin_task_detail_screen.dart';
import 'tasks/admin_tasks_screen.dart';
import 'users/admin_user_add_screen.dart';
import 'users/admin_user_edit_screen.dart';
import 'users/admin_users_screen.dart';

/// Every admin page asks before leaving unsaved edits behind.
GoRoute _page(String path, Widget Function(GoRouterState state) build) =>
    GoRoute(
      path: path,
      onExit: confirmAdminLeave,
      builder: (context, state) => build(state),
    );

/// The whole admin area, shared by the app router and the admin tests.
final adminShellRoute = ShellRoute(
  navigatorKey: AdminShellScreen.navigatorKey,
  // A deep link to a page this server doesn't have lands on the first page
  // of its group that it does have.
  redirect: (context, state) {
    final page = adminPageFor(state.uri.path);
    final server = adminServerType();
    if (page == null || page.availableOn(server)) return null;
    return adminGroupOf(page).pagesOn(server).first.route;
  },
  builder: (context, state, child) => AdminServerScope(
    serverType: adminServerType(),
    child: AdminShellScreen(child: child),
  ),
  routes: [
    _page(Destinations.admin, (_) => const AdminDashboardScreen()),
    _page(
      Destinations.adminGroup,
      (s) => AdminGroupIndexScreen(groupId: s.pathParameters['groupId']!),
    ),
    _page(Destinations.adminAnalytics, (_) => const AdminContentAnalyticsScreen()),
    _page(
      Destinations.adminAnalyticsItems,
      (s) => AdminAnalyticsItemsScreen(query: AdminAnalyticsQuery.fromUri(s.uri)),
    ),
    _page(Destinations.adminUsers, (_) => const AdminUsersScreen()),
    _page(Destinations.adminUsersAdd, (_) => const AdminUserAddScreen()),
    _page(
      Destinations.adminUsersEdit,
      (s) => AdminUserEditScreen(userId: s.pathParameters['userId']!),
    ),
    _page(Destinations.adminLibraries, (_) => const AdminLibrariesScreen()),
    _page(Destinations.adminLibrariesAdd, (_) => const AdminLibraryAddScreen()),
    _page(
      Destinations.adminLibrariesEdit,
      (s) => AdminLibraryEditScreen(libraryId: s.pathParameters['libraryId']!),
    ),
    _page(Destinations.adminSettings, (_) => const AdminGeneralSettingsScreen()),
    _page(
      Destinations.adminSettingsPlayback,
      (_) => Builder(
        builder: (context) => AdminServerScope.isEmby(context)
            ? const AdminEmbyTranscodingScreen()
            : const AdminPlaybackSettingsScreen(),
      ),
    ),
    _page(
      Destinations.adminSettingsResume,
      (_) => const AdminResumeSettingsScreen(),
    ),
    _page(Destinations.adminSettingsStreaming, (_) => const AdminStreamingScreen()),
    _page(Destinations.adminSettingsTrickplay, (_) => const AdminTrickplayScreen()),
    _page(
      Destinations.adminSettingsNetworking,
      (_) => Builder(
        builder: (context) => AdminServerScope.isEmby(context)
            ? AdminConfigFormScreen(page: embyNetworkingPage)
            : const AdminNetworkingScreen(),
      ),
    ),
    _page(Destinations.adminSettingsBranding, (_) => const AdminBrandingScreen()),
    _page(
      Destinations.adminSettingsDisplay,
      (_) => const AdminLibraryDisplayScreen(),
    ),
    _page(
      Destinations.adminSettingsMetadata,
      (_) => const AdminLibraryMetadataScreen(),
    ),
    _page(Destinations.adminSettingsNfo, (_) => const AdminLibraryNfoScreen()),
    _page(Destinations.adminTasks, (_) => const AdminTasksScreen()),
    _page(
      Destinations.adminTasksDetail,
      (s) => AdminTaskDetailScreen(taskId: s.pathParameters['taskId']!),
    ),
    _page(Destinations.adminPlugins, (_) => const AdminPluginsScreen()),
    _page(
      Destinations.adminPluginsDetail,
      (s) => AdminPluginDetailScreen(pluginId: s.pathParameters['pluginId']!),
    ),
    _page(Destinations.adminRepositories, (_) => const AdminRepositoriesScreen()),
    _page(
      Destinations.adminActivity,
      // The dashboard's See all sets ?useractivity=.
      (s) => AdminActivityScreen(
        userActivity: bool.tryParse(s.uri.queryParameters['useractivity'] ?? ''),
      ),
    ),
    _page(Destinations.adminDevices, (_) => const AdminDevicesScreen()),
    _page(Destinations.adminKeys, (_) => const AdminApiKeysScreen()),
    _page(
      Destinations.adminBackups,
      (_) => Builder(
        builder: (context) => AdminServerScope.isEmby(context)
            ? const AdminEmbyBackupsScreen()
            : const AdminBackupsScreen(),
      ),
    ),
    _page(Destinations.adminLogs, (_) => const AdminLogsScreen()),
    _page(Destinations.adminPremiere, (_) => const AdminPremiereScreen()),
    for (final (route, page) in [
      (Destinations.adminDatabase, databasePage),
      (Destinations.adminCinemaIntros, cinemaIntrosPage),
      (Destinations.adminDlna, dlnaPage),
      (Destinations.adminCameraUpload, cameraUploadPage),
    ])
      _page(route, (_) => AdminConfigFormScreen(page: page)),
    _page(
      Destinations.adminConversions,
      (_) => AdminConfigFormScreen(
        page: conversionsPage,
        footer: const AdminSyncJobsList(),
      ),
    ),
    _page(
      Destinations.adminLogsFile,
      // go_router already decodes path parameters, no need for a second decode
      (s) => AdminLogViewerScreen(fileName: s.pathParameters['fileName']!),
    ),
    _page(Destinations.adminLiveTv, (_) => const AdminLiveTvScreen()),
    _page(
      Destinations.adminLiveTvChannels,
      (_) => const AdminLiveTvChannelsScreen(),
    ),
    _page(
      Destinations.adminMetadataEdit,
      (s) => AdminMetadataEditScreen(itemId: s.pathParameters['itemId']!),
    ),
  ],
);
