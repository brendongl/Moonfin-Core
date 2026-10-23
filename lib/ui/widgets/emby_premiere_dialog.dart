import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../navigation/destinations.dart';
import 'adaptive/adaptive_dialog.dart';
import 'overlay_sheet.dart';

final embyPremiereUri = Uri.parse('https://emby.media/premiere');

/// Tells the user a feature needs Emby Premiere. With [saving], for an admin
/// setting, it offers to save anyway, since the server keeps the setting but
/// ignores it without a license, and links to the admin Premiere page. Returns
/// whether they chose to save.
Future<bool> showPremiereRequiredDialog(
  BuildContext context, {
  bool saving = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  final result = await showFocusRestoringDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(l10n.embyPremiereRequiredTitle),
      content: Text(
        saving
            ? l10n.embyPremiereRequiredSaveBody
            : l10n.embyPremiereRequiredBody,
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(saving ? l10n.cancel : l10n.close),
        ),
        adaptiveDialogAction(
          onPressed: () =>
              launchUrl(embyPremiereUri, mode: LaunchMode.externalApplication),
          child: Text(l10n.embyPremiereLearnMore),
        ),
        if (saving) ...[
          adaptiveDialogAction(
            onPressed: () {
              Navigator.of(ctx).pop(false);
              router.push(Destinations.adminPremiere);
            },
            child: Text(l10n.embyPremiereEnterKey),
          ),
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.embyPremiereSaveAnyway),
          ),
        ],
      ],
    ),
  );
  return result ?? false;
}
