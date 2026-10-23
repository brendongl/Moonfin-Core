import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../admin_draft.dart';
import '../widgets/admin_form_styles.dart';

/// Kodi/NFO metadata saver settings, backed by the named `xbmcmetadata`
/// configuration.
class AdminLibraryNfoScreen extends StatefulWidget {
  const AdminLibraryNfoScreen({super.key});

  @override
  State<AdminLibraryNfoScreen> createState() => _AdminLibraryNfoScreenState();
}

class _AdminLibraryNfoScreenState extends State<AdminLibraryNfoScreen>
    with AdminDraftHost {
  static const _key = 'xbmcmetadata';

  late final MediaServerClient _client;
  Map<String, dynamic>? _config;
  List<ServerUser> _users = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = GetIt.instance<MediaServerClient>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _client.adminSystemApi;
      final config = await api.getNamedConfiguration(_key);
      // A failed user list shows the error instead of the form.
      final users = await _client.adminUsersApi.getUsers();
      if (!mounted) return;
      setState(() {
        _config = config;
        _users = users;
        _loading = false;
      });
      hostDraft(
        AdminDraft.single(
          working: config,
          reload: () => api.getNamedConfiguration(_key),
          post: (value) {
            final format = value['ReleaseDateFormat'] as String? ?? '';
            if (format.isEmpty) value['ReleaseDateFormat'] = 'yyyy-MM-dd';
            return api.updateNamedConfiguration(_key, value);
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, AppLocalizations.of(context));
        _loading = false;
      });
    }
  }

  void _set(String key, Object? value) {
    setState(() => _config![key] = value);
    edited();
  }

  Widget _switchTile(String key, String title) {
    return adminSwitchRow(
      title: title,
      anchor: 'nfo.$key',
      value: _config![key] as bool? ?? false,
      onChanged: (v) => _set(key, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final l10n = AppLocalizations.of(context);
    if (_error != null || _config == null) {
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
    final currentUser = _config!['UserId']?.toString() ?? '';
    final userIds = _users.map((u) => u.id).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminLibNfoTitle,
          subtitle: l10n.adminLibNfoHelp,
          icon: Icons.text_snippet_outlined,
        ),
        draftKeyed(
          adminSection(
            context,
            title: l10n.adminDrawerNfo,
            icon: Icons.tune,
            children: [
              adminFieldRow(
                label: l10n.adminLibKodiUser,
                anchor: 'nfo.UserId',
                child: DropdownButtonFormField<String>(
                  initialValue:
                      userIds.contains(currentUser) ? currentUser : '',
                  isExpanded: true,
                  decoration: adminInputDecoration(),
                  items: [
                    DropdownMenuItem(value: '', child: Text(l10n.adminLibNone)),
                    ..._users.map((u) => DropdownMenuItem(
                        value: u.id, child: Text(u.name ?? u.id))),
                  ],
                  // None is saved as '', not null.
                  onChanged: (v) => _set('UserId', v ?? ''),
                ),
              ),
              _switchTile('SaveImagePathsInNfo', l10n.adminLibSaveImagePaths),
              _switchTile(
                  'EnablePathSubstitution', l10n.adminLibPathSubstitution),
              _switchTile(
                  'EnableExtraThumbsDuplication', l10n.adminLibExtraThumbs),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            l10n.adminLibMetadataChangeHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
