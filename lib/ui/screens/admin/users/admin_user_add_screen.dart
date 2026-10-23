import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../../../navigation/destinations.dart';
import '../providers/admin_user_providers.dart';
import '../widgets/admin_form_styles.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';

class AdminUserAddScreen extends ConsumerStatefulWidget {
  const AdminUserAddScreen({super.key});

  @override
  ConsumerState<AdminUserAddScreen> createState() => _AdminUserAddScreenState();
}

class _AdminUserAddScreenState extends ConsumerState<AdminUserAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final MediaServerClient _client;
  late Future<(List<VirtualFolderInfo>, List<Map<String, dynamic>>)> _lists;
  bool _saving = false;

  // Both start off, so a new user sees nothing until granted.
  bool _allFolders = false;
  bool _allChannels = false;
  final _folders = <String>{};
  final _channels = <String>{};

  @override
  void initState() {
    super.initState();
    _client = GetIt.instance<MediaServerClient>();
    _lists = _load();
  }

  Future<(List<VirtualFolderInfo>, List<Map<String, dynamic>>)> _load() async =>
      (
        await _client.adminLibraryApi.getMediaFolders(isHidden: false),
        await _client.adminUsersApi.getChannels(),
      );

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = _client.adminUsersApi;
      final user = await api.createUser(
        _nameController.text.trim(),
        _passwordController.text.isEmpty ? null : _passwordController.text,
      );
      ref.invalidate(adminUsersListProvider);
      // The user exists from here on, so a failed access save still opens
      // their page rather than inviting a second create with the same name.
      try {
        // The new user's own policy with only the access keys set, so nothing
        // else is reset.
        await api.updateUserPolicy(user.id, {
          ...user.policy!.toJson(),
          'EnableAllFolders': _allFolders,
          'EnabledFolders': _allFolders ? <String>[] : _folders.toList(),
          'EnableAllChannels': _allChannels,
          'EnabledChannels': _allChannels ? <String>[] : _channels.toList(),
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.adminUserPolicyUpdateFailed(describeError(e, l10n))),
          ));
        }
      }
      if (mounted) context.pushReplacement(Destinations.adminUser(user.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminUserCreateFailed(describeError(e, l10n)))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _lists,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(describeError(snapshot.error!, l10n)),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => setState(() => _lists = _load()),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          );
        }
        final lists = snapshot.data;
        if (lists == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (folders, channels) = lists;
        return Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              20,
              16,
              MediaQuery.of(context).padding.bottom + 40,
            ),
            children: [
              adminScreenHeader(
                context,
                title: l10n.adminCreateUser,
                icon: Icons.person_add_alt_1_outlined,
              ),
              adminSection(
                context,
                title: l10n.profile,
                icon: Icons.person_outline,
                children: [
                  adminFieldRow(
                    label: l10n.username,
                    child: TextFormField(
                      controller: _nameController,
                      decoration: adminInputDecoration(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l10n.adminUsernameRequired
                          : null,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  adminFieldRow(
                    label: l10n.adminPasswordOptional,
                    child: TextFormField(
                      controller: _passwordController,
                      decoration: adminInputDecoration(),
                      obscureText: true,
                    ),
                  ),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminLibraryAccess,
                icon: Icons.video_library_outlined,
                children: [
                  adminSwitchRow(
                    title: l10n.adminEnableAllLibraryAccess,
                    value: _allFolders,
                    onChanged: (v) => setState(() => _allFolders = v),
                  ),
                  if (!_allFolders)
                    for (final folder in folders)
                      _check(folder.name, folder.itemId, _folders),
                ],
              ),
              if (channels.isNotEmpty)
                adminSection(
                  context,
                  title: l10n.adminChannelAccess,
                  icon: Icons.live_tv_outlined,
                  children: [
                    adminSwitchRow(
                      title: l10n.adminEnableAllChannels,
                      value: _allChannels,
                      onChanged: (v) => setState(() => _allChannels = v),
                    ),
                    if (!_allChannels)
                      for (final channel in channels)
                        _check(
                          '${channel['Name'] ?? channel['Id']}',
                          '${channel['Id']}',
                          _channels,
                        ),
                  ],
                ),
              const SizedBox(height: 24),
              adminSaveButton(
                label: l10n.create,
                saving: _saving,
                onPressed: _submit,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => context.pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _check(String title, String id, Set<String> selected) {
    return CheckboxListTile(
      title: Text(title),
      value: selected.contains(id),
      onChanged: (v) => setState(() {
        if (v == true) {
          selected.add(id);
        } else {
          selected.remove(id);
        }
      }),
    );
  }
}
