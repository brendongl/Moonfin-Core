import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../widgets/admin_form_styles.dart';

Future<void> showRenameLibraryDialog(
  BuildContext context, {
  required String currentName,
  String? libraryId,
  required VoidCallback onRenamed,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: currentName);
  final newName = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(l10n.adminRenameLibrary),
      content: TextField(
        controller: controller,
        decoration: adminInputDecoration(
          label: l10n.adminNewName,
          helper: l10n.adminRenameLibraryWarning,
        ),
        autofocus: true,
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: Text(l10n.rename),
        ),
      ],
    ),
  );
  controller.dispose();

  if (newName == null ||
      newName.isEmpty ||
      newName == currentName ||
      !context.mounted) {
    return;
  }

  try {
    await GetIt.instance<MediaServerClient>()
        .adminLibraryApi
        .renameVirtualFolder(
          currentName,
          newName,
          refreshLibrary: true,
          libraryId: libraryId,
        );
    onRenamed();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminLibraryRenamed(newName))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminRenameFailed(describeError(e, l10n)))),
      );
    }
  }
}

Future<void> showDeleteLibraryDialog(
  BuildContext context, {
  required String libraryName,
  String? libraryId,
  List<String> locations = const [],
  required VoidCallback onDeleted,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(l10n.adminDeleteLibrary),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.adminDeleteLibraryConfirm(libraryName)),
            if (locations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.adminDeleteLibraryLocations),
              const SizedBox(height: 4),
              for (final path in locations)
                Text(path,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await GetIt.instance<MediaServerClient>()
        .adminLibraryApi
        .removeVirtualFolder(
          libraryName,
          refreshLibrary: true,
          libraryId: libraryId,
        );
    onDeleted();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminLibraryDeleted(libraryName))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminLibraryDeleteFailed(describeError(e, l10n)))),
      );
    }
  }
}

/// A scan fills in new and changed files. The other two modes ask every
/// provider again and may replace images and trickplay too.
Future<void> showRefreshItemDialog(
  BuildContext context, {
  required String itemId,
}) async {
  final l10n = AppLocalizations.of(context);
  var mode = 'scan';
  var replaceImages = false;
  var replaceTrickplay = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog.adaptive(
        title: Text(l10n.adminRefreshMetadata),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: mode,
                isExpanded: true,
                decoration: adminInputDecoration(label: l10n.adminRefreshMode),
                items: [
                  DropdownMenuItem(
                      value: 'scan', child: Text(l10n.adminRefreshModeScan)),
                  DropdownMenuItem(
                      value: 'missing',
                      child: Text(l10n.adminRefreshModeMissing)),
                  DropdownMenuItem(
                      value: 'all', child: Text(l10n.adminReplaceAllMetadata)),
                ],
                onChanged: (v) => setDialog(() => mode = v ?? 'scan'),
              ),
              if (mode != 'scan') ...[
                CheckboxListTile(
                  value: replaceImages,
                  onChanged: (v) => setDialog(() => replaceImages = v ?? false),
                  title: Text(l10n.adminReplaceImages),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: replaceTrickplay,
                  onChanged: (v) =>
                      setDialog(() => replaceTrickplay = v ?? false),
                  title: Text(l10n.adminReplaceTrickplayImages),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
              const SizedBox(height: 8),
              Text(l10n.adminRefreshDialogHelp,
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.refresh),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final full = mode != 'scan';
  final refreshMode = full
      ? MetadataRefreshMode.fullRefresh
      : MetadataRefreshMode.defaultRefresh;
  try {
    await GetIt.instance<MediaServerClient>().adminItemsApi.refreshItem(
          itemId,
          recursive: true,
          metadataRefreshMode: refreshMode,
          imageRefreshMode: refreshMode,
          replaceAllMetadata: mode == 'all',
          replaceAllImages: full && replaceImages,
          regenerateTrickplay: full && replaceTrickplay,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminMetadataRefreshRequested)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                l10n.adminMetadataRefreshFailed(describeError(e, l10n)))),
      );
    }
  }
}

/// The image types the fetcher settings tick on or off, Backdrop aside.
const _fetchImageTypes = [
  'Primary', 'Art', 'BoxRear', 'Banner', 'Box', 'Disc', 'Logo', 'Menu', 'Thumb',
];

/// A type's fetcher settings: which [supported] image types to download, and
/// how many backdrops of what width.
/// Returns the new ImageOptions, or null when closed without Done.
Future<List<Map<String, dynamic>>?> showImageOptionsDialog(
  BuildContext context, {
  required String type,
  required List<String> supported,
  required List<Map<String, dynamic>> stored,
  required List<Map<String, dynamic>> defaults,
}) =>
    showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _ImageOptionsDialog(
        type: type,
        supported: supported,
        stored: stored,
        defaults: defaults,
      ),
    );

class _ImageOptionsDialog extends StatefulWidget {
  const _ImageOptionsDialog({
    required this.type,
    required this.supported,
    required this.stored,
    required this.defaults,
  });

  final String type;
  final List<String> supported;
  final List<Map<String, dynamic>> stored;
  final List<Map<String, dynamic>> defaults;

  @override
  State<_ImageOptionsDialog> createState() => _ImageOptionsDialogState();
}

class _ImageOptionsDialogState extends State<_ImageOptionsDialog> {
  late final types = _fetchImageTypes.where(widget.supported.contains).toList();
  late final fetch = {
    for (final t in types) t: ((_config(t)['Limit'] as num?) ?? 0) > 0,
  };
  late final backdrop = _config('Backdrop');
  late final maxBackdrops =
      TextEditingController(text: '${backdrop['Limit'] ?? 0}');
  late final minWidth =
      TextEditingController(text: '${backdrop['MinWidth'] ?? 0}');

  // Stored, then the server's default for the type, then Primary only.
  Map<String, dynamic> _config(String imageType) =>
      widget.stored.where((o) => o['Type'] == imageType).firstOrNull ??
      widget.defaults.where((o) => o['Type'] == imageType).firstOrNull ??
      {'Type': imageType, 'Limit': imageType == 'Primary' ? 1 : 0, 'MinWidth': 0};

  int _number(TextEditingController c, String key) =>
      int.tryParse(c.text.trim()) ?? (backdrop[key] as num? ?? 0).toInt();

  @override
  void dispose() {
    maxBackdrops.dispose();
    minWidth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(String t) => switch (t) {
      'Primary' => l10n.adminMetadataImagePrimary,
      'Art' => l10n.adminImageTypeArt,
      'BoxRear' => l10n.adminImageTypeBoxRear,
      'Banner' => l10n.adminMetadataImageBanner,
      'Box' => l10n.adminImageTypeBox,
      'Disc' => l10n.adminImageTypeDisc,
      'Logo' => l10n.adminMetadataImageLogo,
      'Menu' => l10n.adminImageTypeMenu,
      _ => l10n.adminMetadataImageThumb,
    };
    return AlertDialog.adaptive(
      title: Text(l10n.adminLibImageOptionsTitle(widget.type)),
      content: SingleChildScrollView(
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (types.isNotEmpty)
                Text(l10n.adminLibFetchImages,
                    style: Theme.of(context).textTheme.titleSmall),
              for (final t in types)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label(t)),
                  value: fetch[t],
                  onChanged: (v) => setState(() => fetch[t] = v ?? false),
                ),
              if (widget.supported.contains('Backdrop')) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: maxBackdrops,
                  keyboardType: TextInputType.number,
                  decoration:
                      adminInputDecoration(label: l10n.adminLibMaxBackdrops),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minWidth,
                  keyboardType: TextInputType.number,
                  decoration:
                      adminInputDecoration(label: l10n.adminLibMinBackdropWidth),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([
            for (final t in types)
              {'Type': t, 'Limit': fetch[t]! ? 1 : 0, 'MinWidth': 0},
            // Written even for a type without backdrops.
            {
              'Type': 'Backdrop',
              'Limit': _number(maxBackdrops, 'Limit'),
              'MinWidth': _number(minWidth, 'MinWidth'),
            },
          ]),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}
