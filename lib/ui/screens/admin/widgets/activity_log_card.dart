import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import 'admin_form_styles.dart';
import 'activity_log_ui.dart';

/// A dashboard log panel: the entries of one query, each opening the activity
/// page in the matching view through [onOpen].
class ActivityLogCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ActivityLogEntry> entries;
  final bool showOverview;
  final VoidCallback onOpen;

  const ActivityLogCard({
    super.key,
    required this.title,
    required this.icon,
    required this.entries,
    required this.onOpen,
    this.showOverview = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final listItems = buildActivityListItems(entries, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: adminSectionLabel(context, title, icon: icon)),
            TextButton(onPressed: onOpen, child: Text(l10n.seeAll)),
          ],
        ),
        adminGlassGroup(
          context,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.spaceLg,
                vertical: AppSpacing.spaceMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text(l10n.adminNoRecentActivity)),
                    )
                  else
                    for (final item in listItems)
                      if (item is String)
                        _groupHeader(item, theme)
                      else
                        _entryRow(item as ActivityLogEntry, theme, l10n),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _groupHeader(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _entryRow(ActivityLogEntry entry, ThemeData theme, AppLocalizations l10n) {
    final (rail, icon) = activitySeverityIndicator(entry.severity, theme);
    return InkWell(
      onTap: onOpen,
      borderRadius: AppRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: rail,
                  borderRadius: AppRadius.circular(2),
                ),
              ),
              icon,
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (showOverview &&
                        (entry.shortOverview ?? '').trim().isNotEmpty)
                      Text(
                        entry.shortOverview!,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                activityTimeAgo(entry.date, l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
