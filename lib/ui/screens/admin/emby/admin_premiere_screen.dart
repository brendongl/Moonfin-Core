import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/emby_premiere_dialog.dart';
import '../providers/admin_status_providers.dart';
import '../widgets/admin_form_styles.dart';

/// Emby Premiere's status and key. The key only ever shows as its last four
/// characters.
class AdminPremiereScreen extends ConsumerStatefulWidget {
  const AdminPremiereScreen({super.key});

  @override
  ConsumerState<AdminPremiereScreen> createState() =>
      _AdminPremiereScreenState();
}

class _AdminPremiereScreenState extends ConsumerState<AdminPremiereScreen> {
  EmbyAdminApi get _api => GetIt.instance<MediaServerClient>().embyAdminApi!;
  final _newKey = TextEditingController();
  String? _keyTail;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadKeyTail();
  }

  @override
  void dispose() {
    _newKey.dispose();
    super.dispose();
  }

  Future<void> _loadKeyTail() async {
    try {
      final key = await _api.getPremiereKey();
      if (!mounted) return;
      setState(() => _keyTail = _tail(key));
    } catch (_) {
      // The status card already reports a server that can't be read.
    }
  }

  static String? _tail(String? key) {
    if (key == null || key.isEmpty) return null;
    return '•••• ${key.length > 4 ? key.substring(key.length - 4) : ''}';
  }

  Future<void> _save(String key) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await _api.setPremiereKey(key);
      ref.invalidate(premiereStatusProvider);
      final status = await ref.read(premiereStatusProvider.future);
      if (!mounted) return;
      _newKey.clear();
      setState(() => _keyTail = _tail(key));
      if (key.isNotEmpty && status?.isActive != true) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.adminPremiereKeyRejected)),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.adminSettingsSaveFailed(describeError(e, l10n))),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(premiereStatusProvider);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.paddingOf(context).bottom + 40,
      ),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminDrawerPremiere,
          icon: Icons.workspace_premium_outlined,
        ),
        status.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => adminSection(
            context,
            title: l10n.adminPremiereLoadFailed,
            icon: Icons.error_outline,
            children: [
              ListTile(title: Text(describeError(e, l10n))),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => ref.invalidate(premiereStatusProvider),
                  child: Text(l10n.retry),
                ),
              ),
            ],
          ),
          data: (status) => _buildBody(context, l10n, status),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    PremiereStatus? status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final active = status?.isActive ?? false;
    final (text, icon, color) = active
        ? (l10n.adminPremiereActive, Icons.verified_outlined, scheme.primary)
        : status?.isKeyInvalid ?? false
        ? (l10n.adminPremiereKeyInvalid, Icons.error_outline, scheme.error)
        : (l10n.adminPremiereInactive, Icons.info_outline, scheme.tertiary);
    return adminSection(
      context,
      title: l10n.status,
      icon: Icons.workspace_premium_outlined,
      children: [
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(text),
        ),
        if (_keyTail != null)
          adminFieldRow(
            label: l10n.adminPremiereCurrentKey,
            child: Row(
              children: [
                Expanded(child: Text(_keyTail!)),
                TextButton(
                  onPressed: _saving ? null : () => _save(''),
                  child: Text(l10n.adminPremiereRemoveKey),
                ),
              ],
            ),
          ),
        adminFieldRow(
          label: l10n.adminPremiereNewKey,
          helper: l10n.adminPremiereNewKeyHint,
          anchor: 'premiere.SupporterKey',
          child: TextField(
            controller: _newKey,
            enabled: !_saving,
            autocorrect: false,
            enableSuggestions: false,
            decoration: adminInputDecoration(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ListenableBuilder(
                listenable: _newKey,
                builder: (context, _) => FilledButton(
                  onPressed: _saving || _newKey.text.trim().isEmpty
                      ? null
                      : () => _save(_newKey.text.trim()),
                  child: Text(l10n.adminPremiereSaveKey),
                ),
              ),
              if (!active)
                OutlinedButton(
                  onPressed: () => launchUrl(
                    embyPremiereUri,
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(l10n.embyPremiereLearnMore),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
