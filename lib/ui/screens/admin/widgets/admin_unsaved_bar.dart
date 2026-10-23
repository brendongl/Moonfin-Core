import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../admin_draft.dart';

/// Discard and Save for the page on screen, shown only while it has unsaved
/// edits.
class AdminUnsavedBar extends StatelessWidget {
  const AdminUnsavedBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminDraft?>(
      valueListenable: AdminDraft.active,
      builder: (context, draft, _) {
        if (draft == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: draft,
          builder: (context, _) => AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: draft.isDirty || draft.saving || draft.error != null
                ? _Bar(draft: draft)
                : const SizedBox(width: double.infinity),
          ),
        );
      },
    );
  }
}

class _Bar extends StatefulWidget {
  const _Bar({required this.draft});

  final AdminDraft draft;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  AdminDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    // A "Settings saved" snackbar from the last save sits over the bottom of
    // the window, right where the bar comes back for the next edit, and would
    // swallow taps on Save. The bar shows its own errors, so it takes over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    });
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    if (await draft.save()) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.adminSettingsSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final error = draft.error;
    final warn = AppColorScheme.recordingScheduled;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(warn.withValues(alpha: 0.10), scheme.surface),
          border: Border(top: BorderSide(color: warn.withValues(alpha: 0.45))),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: warn, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error != null
                      ? l10n.adminSettingsSaveFailed(describeError(error, l10n))
                      : l10n.adminUnsavedChanges,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: error != null ? scheme.error : null,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: draft.saving ? null : draft.discard,
                child: Text(l10n.adminDiscard),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: draft.saving || !draft.isDirty
                    ? null
                    : () => _save(context),
                child: draft.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
