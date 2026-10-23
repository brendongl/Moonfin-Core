import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../navigation/destinations.dart';
import '../admin_nav.dart';
import '../providers/admin_status_providers.dart';

/// Marks an Emby setting that Premiere gates while the server has no active
/// license. Shows nothing on Jellyfin.
class PremiereNote extends ConsumerWidget {
  const PremiereNote({
    super.key,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.message,
  });

  final EdgeInsetsGeometry margin;

  /// What Premiere unlocks here, in place of the note about a setting.
  final String Function(AppLocalizations l10n)? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AdminServerScope.isEmby(context)) return const SizedBox.shrink();
    final status = ref.watch(premiereStatusProvider).valueOrNull;
    if (status == null || status.isActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message?.call(l10n) ?? l10n.adminPremiereNote,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          TextButton(
            onPressed: () => context.push(Destinations.adminPremiere),
            child: Text(l10n.embyPremiereEnterKey),
          ),
        ],
      ),
    );
  }
}
