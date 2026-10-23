import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../admin_draft.dart';
import '../widgets/admin_form_styles.dart';

/// Server-wide library display settings (folder view, collection grouping,
/// external suggestions) plus the date-added behavior from the named `metadata`
/// configuration.
class AdminLibraryDisplayScreen extends StatefulWidget {
  const AdminLibraryDisplayScreen({super.key});

  @override
  State<AdminLibraryDisplayScreen> createState() =>
      _AdminLibraryDisplayScreenState();
}

class _AdminLibraryDisplayScreenState extends State<AdminLibraryDisplayScreen>
    with AdminDraftHost {
  late final AdminSystemApi _api;
  Map<String, dynamic>? _config;
  Map<String, dynamic>? _metadata;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = GetIt.instance<MediaServerClient>().adminSystemApi;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _api.getServerConfiguration();
      // No fallback, because saving a blank metadata config would flip the
      // date added behavior to the server default.
      final metadata = await _api.getNamedConfiguration('metadata');
      if (!mounted) return;
      setState(() {
        _config = config;
        _metadata = metadata;
        _loading = false;
      });
      hostDraft(AdminDraft({
        'config': AdminDraftTarget(
          working: config,
          reload: _api.getServerConfiguration,
          post: _api.updateServerConfiguration,
        ),
        'metadata': AdminDraftTarget(
          working: metadata,
          reload: () => _api.getNamedConfiguration('metadata'),
          post: (value) => _api.updateNamedConfiguration('metadata', value),
        ),
      }));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, AppLocalizations.of(context));
        _loading = false;
      });
    }
  }

  void _set(Map<String, dynamic> target, String key, Object? value) {
    setState(() => target[key] = value);
    edited();
  }

  Widget _switchTile(String key, String title, {bool fallback = false}) {
    return adminSwitchRow(
      title: title,
      anchor: 'display.$key',
      value: _config![key] as bool? ?? fallback,
      onChanged: (v) => _set(_config!, key, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final l10n = AppLocalizations.of(context);
    if (_error != null || _config == null || _metadata == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminSettingsLoadFailed,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error ?? l10n.adminUnknownError,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    final bottomSafe = MediaQuery.of(context).padding.bottom;
    // The server default is true when the key is missing.
    final useFileTime =
        _metadata!['UseFileCreationTimeForDateAdded'] as bool? ?? true;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminLibDisplayTitle,
          icon: Icons.grid_view,
        ),
        draftKeyed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adminSection(
                context,
                title: l10n.adminLibDateAddedSection,
                icon: Icons.event_outlined,
                children: [
                  adminFieldRow(
                    label: l10n.adminLibDateAddedLabel,
                    anchor: 'display.UseFileCreationTimeForDateAdded',
                    child: DropdownButtonFormField<bool>(
                      initialValue: useFileTime,
                      isExpanded: true,
                      decoration: adminInputDecoration(),
                      items: [
                        DropdownMenuItem(
                            value: false,
                            child: Text(l10n.adminLibDateAddedImport)),
                        DropdownMenuItem(
                            value: true, child: Text(l10n.adminLibDateAddedFile)),
                      ],
                      onChanged: (v) => _set(_metadata!,
                          'UseFileCreationTimeForDateAdded', v ?? true),
                    ),
                  ),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminLibDisplaySection,
                icon: Icons.tune,
                children: [
                  _switchTile('EnableFolderView', l10n.adminLibFolderView),
                  _switchTile('DisplaySpecialsWithinSeasons',
                      l10n.adminLibSpecialsInSeasons,
                      fallback: true),
                  _switchTile('EnableGroupingMoviesIntoCollections',
                      l10n.adminLibGroupMovies),
                  _switchTile('EnableGroupingShowsIntoCollections',
                      l10n.adminLibGroupShows),
                  _switchTile('EnableExternalContentInSuggestions',
                      l10n.adminLibExternalSuggestions,
                      fallback: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
