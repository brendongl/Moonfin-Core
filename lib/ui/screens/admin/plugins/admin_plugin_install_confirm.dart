import 'package:flutter/material.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';

/// Plugins from the official repository install without asking.
const _trustedRepoUrl = 'https://repo.jellyfin.org/';

/// Asks before installing [version] from any other repository. True means
/// go ahead.
Future<bool> confirmPluginInstall(
  BuildContext context,
  VersionInfo version,
) async {
  if (version.repositoryUrl.startsWith(_trustedRepoUrl)) return true;
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(l10n.adminPluginInstallConfirmTitle),
      content: Text(l10n.adminPluginInstallDisclaimer),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.install),
        ),
      ],
    ),
  );
  return confirmed == true;
}
