import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../navigation/destinations.dart';
import '../providers/admin_user_providers.dart';
import '../widgets/admin_form_styles.dart';
import 'admin_library_dialogs.dart';

class AdminLibrariesScreen extends ConsumerWidget {
  const AdminLibrariesScreen({super.key});

  static const _collectionIcons = <String, IconData>{
    'movies': Icons.movie,
    'tvshows': Icons.tv,
    'music': Icons.music_note,
    'musicvideos': Icons.music_video,
    'books': Icons.book,
    'photos': Icons.photo,
    'homevideos': Icons.videocam,
    'boxsets': Icons.collections,
    'playlists': Icons.playlist_play,
    'mixed': Icons.folder,
  };

  static IconData iconForType(String? type) =>
      _collectionIcons[type?.toLowerCase()] ?? Icons.folder;

  static String labelForType(String? type, AppLocalizations l10n) {
    if (type == null || type.isEmpty) {
      return l10n.mixedContent;
    }

    switch (type.toLowerCase()) {
      case 'movies':
        return l10n.movies;
      case 'tvshows':
        return l10n.tvShows;
      case 'music':
        return l10n.music;
      case 'musicvideos':
        return l10n.musicVideos;
      case 'books':
        return l10n.books;
      case 'photos':
        return l10n.photos;
      case 'homevideos':
        return l10n.homeVideos;
      case 'boxsets':
        return l10n.collections;
      case 'playlists':
        return l10n.playlists;
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final listBottomPadding = bottomSafe + 120;
    final actionsBottom = bottomSafe + 16;
    final librariesAsync = ref.watch(adminLibrariesProvider);
    // Scanning every library starts the RefreshLibrary task, so the button
    // follows that task's state.
    final scanTask = ref
        .watch(adminTasksProvider)
        .valueOrNull
        ?.where((t) => t.key == 'RefreshLibrary')
        .firstOrNull;
    final scanTaskId = scanTask?.id;
    final scanning = scanTask != null && scanTask.state != 'Idle';
    final scanProgress = scanTask?.state == 'Running'
        ? scanTask?.currentProgressPercentage
        : null;

    return librariesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminLibrariesLoadFailed,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              describeError(e, l10n),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(adminLibrariesProvider),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
      data: (libraries) => Stack(
        children: [
          libraries.isEmpty
              ? ListView(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, listBottomPadding),
                  children: [
                    adminScreenHeader(
                      context,
                      title: l10n.adminDrawerLibraries,
                      icon: Icons.video_library_outlined,
                    ),
                    const SizedBox(height: 48),
                    Center(child: Text(l10n.adminNoLibraries)),
                  ],
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, listBottomPadding),
                  itemCount: libraries.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return adminScreenHeader(
                        context,
                        title: l10n.adminDrawerLibraries,
                        icon: Icons.video_library_outlined,
                      );
                    }
                    final lib = libraries[index - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.spaceMd),
                      child: adminGlassGroup(
                        context,
                        children: [
                          ListTile(
                            leading: _libraryIcon(iconForType(lib.collectionType)),
                            title: Text(
                              lib.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  labelForType(lib.collectionType, l10n),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (lib.locations.isNotEmpty)
                                  Text(
                                    lib.locations.join(', '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            fontFamily: 'monospace',
                                            fontSize: 11),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            isThreeLine: lib.locations.isNotEmpty,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.spaceLg,
                              vertical: 4,
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) =>
                                  _onAction(context, ref, value, lib),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'refresh',
                                  child: ListTile(
                                    leading: const Icon(Icons.refresh),
                                    title: Text(l10n.adminRefreshLibrary),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: const Icon(Icons.edit),
                                    title: Text(l10n.edit),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.drive_file_rename_outline),
                                    title: Text(l10n.rename),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: const Icon(Icons.delete),
                                    title: Text(l10n.delete),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => context
                                .push(Destinations.adminLibrary(lib.itemId)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          Positioned(
            left: 16,
            right: 16,
            bottom: actionsBottom,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                // A second start would cancel the running scan, so the button
                // waits for the task to go idle.
                FloatingActionButton.extended(
                  heroTag: 'scan',
                  onPressed: scanning ? null : () => _scanAll(context, scanTaskId),
                  icon: scanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(scanProgress == null
                      ? l10n.adminRefreshAllLibraries
                      : '${l10n.adminRefreshAllLibraries} ${scanProgress.round()}%'),
                ),
                FloatingActionButton.extended(
                  heroTag: 'add',
                  onPressed: () => context.push(Destinations.adminLibrariesAdd),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.adminAddLibrary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _libraryIcon(IconData icon) {
    final accent = AppColorScheme.accent;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: AppRadius.circular(11),
        color: accent.withValues(alpha: 0.14),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
      ),
      child: Icon(icon, size: 20, color: accent),
    );
  }

  void _onAction(
      BuildContext context, WidgetRef ref, String action, VirtualFolderInfo lib) {
    switch (action) {
      case 'refresh':
        showRefreshItemDialog(context, itemId: lib.itemId);
      case 'edit':
        context.push(Destinations.adminLibrary(lib.itemId));
      case 'rename':
        showRenameLibraryDialog(
          context,
          currentName: lib.name,
          libraryId: lib.itemId,
          onRenamed: () => ref.invalidate(adminLibrariesProvider),
        );
      case 'delete':
        showDeleteLibraryDialog(
          context,
          libraryName: lib.name,
          libraryId: lib.itemId,
          locations: lib.locations,
          onDeleted: () => ref.invalidate(adminLibrariesProvider),
        );
    }
  }

  Future<void> _scanAll(BuildContext context, String? taskId) async {
    final l10n = AppLocalizations.of(context);
    final client = GetIt.instance<MediaServerClient>();
    try {
      // /Library/Refresh queues the same scan when the task list is missing.
      if (taskId != null) {
        await client.adminTasksApi.startTask(taskId);
      } else {
        await client.adminLibraryApi.refreshLibrary();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminLibraryScanStarted)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminScanFailed(describeError(e, l10n)))),
        );
      }
    }
  }
}
