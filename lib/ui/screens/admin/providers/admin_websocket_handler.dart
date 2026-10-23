import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_core/server_core.dart';

import '../../../../di/providers.dart';
import 'admin_status_providers.dart';
import 'admin_user_providers.dart';

class AdminWebSocketHandler extends ConsumerStatefulWidget {
  final Widget child;

  const AdminWebSocketHandler({super.key, required this.child});

  @override
  ConsumerState<AdminWebSocketHandler> createState() =>
      _AdminWebSocketHandlerState();
}

class _AdminWebSocketHandlerState extends ConsumerState<AdminWebSocketHandler> {
  StreamSubscription<ServerWebSocketMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(socketHandlerProvider).events.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onEvent(ServerWebSocketMessage event) {
    // Task and session lists follow their own feeds (adminTasksProvider,
    // adminSessionsProvider), so only the one-off events are handled here.
    switch (event) {
      case LibraryChangedMessage():
        ref.invalidate(adminLibrariesProvider);
      // Anything can change across a restart, so every cached list is dropped.
      case ServerRestartingMessage():
      case ServerShuttingDownMessage():
        ref
          ..invalidate(adminInstalledPluginsProvider)
          ..invalidate(adminAvailablePackagesProvider)
          ..invalidate(adminRepositoriesProvider)
          ..invalidate(adminUsersListProvider)
          ..invalidate(adminLibrariesProvider)
          ..invalidate(adminDevicesProvider)
          ..invalidate(adminNotificationSummaryProvider);
      case ServerEventMessage(:final type):
        switch (type) {
          case 'PackageInstallationCompleted':
          case 'PackageInstallationFailed':
          case 'PackageInstallationCancelled':
          case 'PackageUninstalled':
          case 'RestartRequired':
            ref.invalidate(adminInstalledPluginsProvider);
            ref.invalidate(adminAvailablePackagesProvider);
            ref.invalidate(adminRepositoriesProvider);
            ref.invalidate(adminNotificationSummaryProvider);
          case 'UserDeleted':
          case 'UserUpdated':
            ref.invalidate(adminUsersListProvider);
          default:
            break;
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}