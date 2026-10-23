import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'admin_nav.dart';
import 'admin_shell_screen.dart';
import 'widgets/admin_form_styles.dart';
import 'widgets/admin_settings_search.dart';

/// A group's pages on a phone, where there is no room for the page list
/// beside the content. Also holds the settings search.
class AdminGroupIndexScreen extends StatelessWidget {
  const AdminGroupIndexScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final group = adminGroupById(groupId) ?? adminGroups.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        adminScreenHeader(context, title: group.title(l10n), icon: group.icon),
        const AdminSettingsSearch(expandResults: true),
        const SizedBox(height: 12),
        adminListCard(
          child: Column(
            children: [
              for (final page in group.pagesOn(AdminServerScope.of(context)))
                AdminPageTile(page: page, showChevron: true),
            ],
          ),
        ),
      ],
    );
  }
}
