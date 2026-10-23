import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../providers/admin_user_providers.dart';
import 'admin_form_styles.dart';
import 'admin_settings_search.dart';

class ServerActionsCard extends ConsumerWidget {
  final MediaServerClient client;
  final bool canRestart;

  const ServerActionsCard({
    super.key,
    required this.client,
    required this.canRestart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scanTask = ref
        .watch(adminTasksProvider)
        .valueOrNull
        ?.where((t) => t.key == 'RefreshLibrary')
        .firstOrNull;
    final scanTaskId = scanTask?.id;
    final scanning = scanTask != null && scanTask.state != 'Idle';
    return AdminSettingAnchor(
      id: 'dashboard.ServerActions',
      child: adminSection(
        context,
        title: l10n.adminServerActions,
        icon: Icons.settings_power,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.spaceLg,
              vertical: AppSpacing.spaceMd,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(l10n.adminScanAllLibraries),
                  onPressed: scanTaskId == null || scanning
                      ? null
                      : () => _scan(context, scanTaskId),
                ),
                if (canRestart)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l10n.adminRestartServer),
                    onPressed: () => _confirmAction(
                      context,
                      title: l10n.adminRestartServer,
                      message: l10n.adminRestartServerConfirmation,
                      onConfirm: () async {
                        await client.adminSystemApi.restartServer();
                        if (!context.mounted) return;
                        await _showRestartMessage(context);
                      },
                    ),
                  ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.power_settings_new),
                  label: Text(l10n.adminShutdownServer),
                  onPressed: () => _confirmAction(
                    context,
                    title: l10n.adminShutdownServer,
                    message: l10n.adminShutdownServerConfirmation,
                    onConfirm: () async {
                      await client.adminSystemApi.shutdownServer();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Starts the library scan task, which, unlike POST /Library/Refresh,
  /// doesn't cancel and restart a scan that's already running.
  Future<void> _scan(BuildContext context, String taskId) async {
    final l10n = AppLocalizations.of(context);
    try {
      await client.adminTasksApi.startTask(taskId);
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

  Future<void> _showRestartMessage(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PopScope(
        canPop: true,
        child: AlertDialog.adaptive(
          title: Text(l10n.adminServerRebootInProgress),
          content: Text(l10n.adminServerRebootMessage),
          actions: [
            adaptiveDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.ok),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(title),
        content: Text(message),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await onConfirm();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorGeneric(describeError(e, l10n)))),
          );
        }
      }
    }
  }
}
