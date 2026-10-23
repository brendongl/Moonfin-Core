import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../../util/platform_detection.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../../detail/modern/widgets/details_tab_bar.dart';
import '../admin_draft.dart';
import '../providers/admin_user_providers.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/filesystem_browser.dart';
import 'library_options_defaults.dart';
import 'library_options_form.dart';

class AdminLibraryEditScreen extends ConsumerStatefulWidget {
  final String libraryId;
  const AdminLibraryEditScreen({super.key, required this.libraryId});

  @override
  ConsumerState<AdminLibraryEditScreen> createState() =>
      _AdminLibraryEditScreenState();
}

class _AdminLibraryEditScreenState
    extends ConsumerState<AdminLibraryEditScreen> with AdminDraftHost {
  static const _eq = DeepCollectionEquality();

  int _selectedTab = 0;
  final _tabFocusNodes = <int, FocusNode>{};
  late final MediaServerClient _client;

  VirtualFolderInfo? _library;
  List<String> _paths = [];

  /// The draft's working LibraryOptions.
  Map<String, dynamic> _options = {};

  /// A copy of what the draft last loaded or saved, so a path change can tell
  /// the unsaved edits apart and carry them onto the reloaded options.
  Map<String, dynamic> _baseline = {};
  Map<String, dynamic> _available = const {};
  List<Map<String, dynamic>> _cultures = const [];
  List<Map<String, dynamic>> _countries = const [];

  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _showBrowser = false;

  @override
  void initState() {
    super.initState();
    _client = GetIt.instance<MediaServerClient>();
    _loadLibrary();
  }

  FocusNode _tabNode(int index) {
    return _tabFocusNodes.putIfAbsent(
        index, () => FocusNode(debugLabel: 'admin_library_tab_$index'));
  }

  @override
  void dispose() {
    draft?.removeListener(_trackBaseline);
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  static T _copy<T>(T value) => jsonDecode(jsonEncode(value)) as T;

  Future<VirtualFolderInfo> _fetchLibrary() async {
    final folders = await _client.adminLibraryApi.getVirtualFolders();
    return folders.firstWhere(
      (f) => f.itemId == widget.libraryId,
      orElse: () => throw Exception('Library not found'),
    );
  }

  Map<String, dynamic> _seeded(VirtualFolderInfo lib) => seedLibraryOptions(
      _copy<Map<String, dynamic>>(lib.libraryOptions ?? {}), _available);

  Future<void> _loadLibrary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lib = await _fetchLibrary();
      // Without the language and country lists the dropdowns just stay empty.
      final cultures = await _client.adminSystemApi
          .getCultures()
          .catchError((_) => <Map<String, dynamic>>[]);
      final countries = await _client.adminSystemApi
          .getCountries()
          .catchError((_) => <Map<String, dynamic>>[]);
      final available = await _client.adminLibraryApi
          .getAvailableLibraryOptions(lib.collectionType)
          .catchError((_) => <String, dynamic>{});
      if (!mounted) return;
      _available = available;
      _cultures = cultures;
      _countries = countries;
      _host(lib);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, AppLocalizations.of(context));
        _loading = false;
      });
    }
  }

  /// Hosts a draft of [lib]'s options with [pending] edits laid on top, so
  /// both the working map and the draft's original carry the server's paths.
  void _host(VirtualFolderInfo lib, [Map<String, dynamic> pending = const {}]) {
    final options = _seeded(lib);
    final target = AdminDraftTarget(
      working: options,
      reload: () async => _seeded(await _fetchLibrary()),
      post: (value) async {
        await _client.adminLibraryApi
            .updateLibraryOptions(widget.libraryId, value);
        if (mounted) ref.invalidate(adminLibrariesProvider);
      },
    );
    _baseline = _copy(options);
    options.addAll(pending);
    setState(() {
      _library = lib;
      _paths = List<String>.from(lib.locations);
      _options = options;
    });
    draft?.removeListener(_trackBaseline);
    hostDraft(AdminDraft({'options': target})..addListener(_trackBaseline));
    if (pending.isNotEmpty) edited();
  }

  /// A clean draft means the working map is what the server has.
  void _trackBaseline() {
    final d = draft;
    if (d != null && !d.isDirty && !d.saving) _baseline = _copy(_options);
  }

  /// Reloads the library after every path change, else Save would post the
  /// old PathInfos and the server would recreate or drop folders.
  Future<void> _reloadAfterPathChange() async {
    final pending = <String, dynamic>{
      for (final k in {..._options.keys, ..._baseline.keys})
        if (k != 'PathInfos' && !_eq.equals(_options[k], _baseline[k]))
          k: _options[k],
    };
    final lib = await _fetchLibrary();
    if (!mounted) return;
    _host(lib, pending);
    ref.invalidate(adminLibrariesProvider);
  }

  Future<void> _addPath(String path) async {
    if (_paths.contains(path)) return;
    setState(() => _busy = true);
    try {
      await _client.adminLibraryApi
          .addMediaPath(
            _library!.name,
            path,
            refreshLibrary: true,
            libraryId: _library!.itemId,
          );
      await _reloadAfterPathChange();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminAddPathFailed(describeError(e, l10n)))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showBrowser = false;
        });
      }
    }
  }

  Future<void> _removePath(String path) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.adminRemovePath),
        content: Text(l10n.adminRemovePathConfirm(path)),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _client.adminLibraryApi
          .removeMediaPath(
            _library!.name,
            path,
            refreshLibrary: true,
            libraryId: _library!.itemId,
          );
      await _reloadAfterPathChange();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminRemovePathFailed(describeError(e, l10n)))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminLibraryLoadFailed,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(
                onPressed: _loadLibrary, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    final showPaths = _library!.collectionType != 'boxsets';
    final tabs = [
      if (showPaths) (l10n.adminLibraryTabPaths, _buildPathsTab),
      (l10n.adminLibraryTabOptions, _buildOptionsTab),
      (l10n.adminLibraryTabDownloaders, _buildDownloadersTab),
    ];
    final selected = _selectedTab.clamp(0, tabs.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: adminScreenHeader(
            context,
            title: _library!.name,
            subtitle: _library!.collectionType,
            icon: Icons.folder_open,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: DetailsTabBar(
            segmented: true,
            wrap: PlatformDetection.useMobileUi,
            labels: [for (final t in tabs) t.$1],
            selectedIndex: selected,
            onSelect: (i) => setState(() => _selectedTab = i),
            focusNodeFor: _tabNode,
          ),
        ),
        Expanded(
          child: draftKeyed(
            IndexedStack(
              index: selected,
              children: [for (final t in tabs) t.$2()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPathsTab() {
    final l10n = AppLocalizations.of(context);
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomSafe + 40),
      children: [
        adminSection(
          context,
          title: l10n.adminLibraryTabPaths,
          icon: Icons.folder_outlined,
          children: [
            ..._paths.map((path) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(path,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: l10n.adminRemovePath,
                    onPressed: _busy ? null : () => _removePath(path),
                  ),
                  dense: true,
                )),
            if (_paths.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.adminNoMediaPaths),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!_showBrowser)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed:
                  _busy ? null : () => setState(() => _showBrowser = true),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminAddPath),
            ),
          )
        else ...[
          Row(
            children: [
              Text(l10n.adminBrowseFilesystem,
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _showBrowser = false),
                child: Text(l10n.cancel),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 350,
            child: FilesystemBrowser(onPathSelected: _addPath),
          ),
        ],
      ],
    );
  }

  Widget _buildOptionsTab() => _optionsList(LibraryOptionsPart.options);

  Widget _buildDownloadersTab() =>
      _optionsList(LibraryOptionsPart.downloaders);

  Widget _optionsList(LibraryOptionsPart part) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomSafe + 40),
      children: [
        LibraryOptionsForm(
          part: part,
          options: _options,
          available: _available,
          collectionType: _library!.collectionType,
          cultures: _cultures,
          countries: _countries,
          onChanged: edited,
        ),
      ],
    );
  }
}
