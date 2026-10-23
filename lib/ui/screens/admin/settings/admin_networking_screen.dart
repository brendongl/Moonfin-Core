import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../admin_draft.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/filesystem_browser.dart';
import 'admin_number_input.dart';

const _publishedKey = 'PublishedServerUriBySubnet';

class AdminNetworkingScreen extends StatefulWidget {
  const AdminNetworkingScreen({super.key});

  @override
  State<AdminNetworkingScreen> createState() => _AdminNetworkingScreenState();
}

class _AdminNetworkingScreenState extends State<AdminNetworkingScreen>
    with AdminDraftHost {
  late final AdminSystemApi _api;
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;
  bool _showCertBrowser = false;

  /// Bumped when the browser picks a certificate, so the path field shows it.
  /// Keying on the value would rebuild the field on every keystroke.
  int _certPicks = 0;
  final _listControllers = <String, TextEditingController>{};

  // PublishedServerUriBySubnet is read as one `all=` entry, or `internal=`
  // and `external=` entries. Other entries (a subnet or an interface) are
  // kept and listed on their own.
  bool _samePublished = true;
  String _pubAll = '';
  String _pubInternal = '';
  String _pubExternal = '';
  List<String> _pubOther = [];
  int? _pubRevision;

  @override
  void initState() {
    super.initState();
    _api = GetIt.instance<MediaServerClient>().adminSystemApi;
    _load();
  }

  @override
  void dispose() {
    for (final c in _listControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _api.getNamedConfiguration('network');
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
      });
      // The server replaces the whole NetworkConfiguration on save, so the
      // full map goes back, keeping the keys this page doesn't show.
      hostDraft(
        AdminDraft.single(
          working: config,
          reload: () => _api.getNamedConfiguration('network'),
          post: (value) => _api.updateNamedConfiguration('network', value),
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

  List<String> _strings(String key) =>
      [for (final v in (_config![key] as List<dynamic>?) ?? const []) '$v'];

  void _parsePublished() {
    _pubRevision = draft?.revision;
    final entries = _strings(_publishedKey);
    _pubAll = _pubInternal = _pubExternal = '';
    _pubOther = [];
    if (entries.length == 1 && !entries.first.contains('=')) {
      _pubAll = entries.first;
    } else {
      for (final entry in entries) {
        final split = entry.indexOf('=');
        final uri = entry.substring(split + 1);
        switch (split < 0 ? '' : entry.substring(0, split)) {
          case 'all':
            _pubAll = uri;
          case 'internal':
            _pubInternal = uri;
          case 'external':
            _pubExternal = uri;
          default:
            _pubOther.add(entry);
        }
      }
    }
    _samePublished =
        _pubAll.isNotEmpty || (_pubInternal.isEmpty && _pubExternal.isEmpty);
  }

  void _writePublished() {
    final all = _pubAll.trim();
    final internal = _pubInternal.trim();
    final external = _pubExternal.trim();
    _set(_publishedKey, [
      if (_samePublished && all.isNotEmpty) 'all=$all',
      if (!_samePublished && internal.isNotEmpty) 'internal=$internal',
      if (!_samePublished && external.isNotEmpty) 'external=$external',
      ..._pubOther,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final l10n = AppLocalizations.of(context);
    if (_error != null || _config == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminNetworkingLoadFailed,
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
    // Discard and Save replace the working map, so read it again.
    if (_pubRevision != draft?.revision) _parsePublished();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminNetworkingTitle,
          subtitle: l10n.adminNetworkingRestartWarning,
          icon: Icons.lan_outlined,
        ),
        draftKeyed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adminSection(
                context,
                title: l10n.adminNetworkingSectionServerAddress,
                icon: Icons.dns_outlined,
                children: [
                  _portField('InternalHttpPort', l10n.adminNetworkingLocalHttpPort,
                      helper: l10n.adminNetworkingLocalHttpPortHelp),
                  _switchTile('EnableHttps', l10n.adminNetworkingEnableHttps,
                      subtitle: l10n.adminNetworkingEnableHttpsHelp),
                  _portField('InternalHttpsPort',
                      l10n.adminNetworkingLocalHttpsPort,
                      helper: l10n.adminNetworkingLocalHttpsPortHelp),
                  _textField('BaseUrl', l10n.adminNetworkingBaseUrl,
                      helper: l10n.adminNetworkingBaseUrlHelp,
                      hint: l10n.adminNetworkingBaseUrlHint),
                  _listField('LocalNetworkAddresses',
                      l10n.adminNetworkingBindAddress,
                      helper: l10n.adminNetworkingBindAddressHelp,
                      hint: l10n.adminNetworkingAddressHint),
                  _listField('LocalNetworkSubnets',
                      l10n.adminNetworkingLocalSubnets,
                      helper: l10n.adminNetworkingLanNetworksHelp,
                      hint: l10n.adminNetworkingAddressHint),
                  _listField('KnownProxies', l10n.adminNetworkingKnownProxies,
                      helper: l10n.adminNetworkingKnownProxiesHelp,
                      hint: l10n.adminNetworkingProxyHint),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminNetworkingSectionHttps,
                icon: Icons.lock_outline,
                children: [
                  _switchTile('RequireHttps', l10n.adminNetworkingRequireHttps,
                      subtitle: l10n.adminNetworkingRequireHttpsHint),
                  _certPathField(l10n),
                  _textField('CertificatePassword',
                      l10n.adminNetworkingCertPassword,
                      helper: l10n.adminNetworkingCertPasswordHelp,
                      obscure: true),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminNetworkingSectionRemoteAccess,
                icon: Icons.public,
                children: [
                  _switchTile('EnableRemoteAccess', l10n.adminNetworkingAllowRemote,
                      subtitle: l10n.adminNetworkingAllowRemoteHelp),
                  _listField('RemoteIPFilter',
                      l10n.adminNetworkingRemoteIpFilterLabel,
                      helper: l10n.adminNetworkingRemoteIpFilterHelp,
                      hint: l10n.adminNetworkingAddressHint),
                  _filterModeField(l10n),
                  _portField('PublicHttpPort', l10n.adminNetworkingPublicHttpPort,
                      helper: l10n.adminNetworkingPublicHttpPortHelp),
                  _portField('PublicHttpsPort',
                      l10n.adminNetworkingPublicHttpsPort,
                      helper: l10n.adminNetworkingPublicHttpsPortHelp),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminNetworkingSectionIpProtocols,
                icon: Icons.settings_input_antenna,
                children: [
                  _switchTile('EnableIPv4', l10n.adminNetworkingEnableIpv4),
                  _switchTile('EnableIPv6', l10n.adminNetworkingEnableIpv6),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminNetworkingSectionDiscovery,
                icon: Icons.wifi_tethering,
                children: [
                  _switchTile('AutoDiscovery', l10n.adminNetworkingAutoDiscoveryLabel,
                      subtitle: l10n.adminNetworkingAutoDiscoveryHelp),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminNetworkingSectionFirewall,
                icon: Icons.link,
                children: _publishedRows(l10n),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _publishedRows(AppLocalizations l10n) {
    Widget uriField(String label, String helper, String value,
            ValueChanged<String> onChanged) =>
        adminFieldRow(
          label: label,
          helper: helper,
          child: TextFormField(
            // The switch swaps these fields in place, and a key per field
            // keeps one field's text from showing up in the next.
            key: ValueKey(label),
            initialValue: value,
            decoration: adminInputDecoration(),
            keyboardType: TextInputType.url,
            onChanged: (v) {
              onChanged(v);
              _writePublished();
            },
          ),
        );

    return [
      adminSwitchRow(
        title: l10n.adminNetworkingSamePublishedUri,
        anchor: 'networking.$_publishedKey',
        value: _samePublished,
        onChanged: (v) {
          _samePublished = v;
          _writePublished();
        },
      ),
      if (_samePublished)
        uriField(l10n.adminNetworkingPublishedUri,
            l10n.adminNetworkingPublishedUriHelp, _pubAll, (v) => _pubAll = v)
      else ...[
        uriField(l10n.adminNetworkingInternalUri,
            l10n.adminNetworkingInternalUriHelp, _pubInternal,
            (v) => _pubInternal = v),
        uriField(l10n.adminNetworkingExternalUri,
            l10n.adminNetworkingExternalUriHelp, _pubExternal,
            (v) => _pubExternal = v),
      ],
      adminFieldRow(
        label: l10n.adminNetworkingOtherPublishedUris,
        helper: l10n.adminNetworkingOtherPublishedUrisHelp,
        child: _listEditor(
          id: 'publishedOther',
          items: _pubOther,
          hint: l10n.adminNetworkingOtherPublishedUriHint,
          onChanged: (items) {
            _pubOther = items;
            _writePublished();
          },
        ),
      ),
    ];
  }

  Widget _textField(
    String key,
    String label, {
    String? helper,
    String? hint,
    bool obscure = false,
  }) {
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'networking.$key',
      child: TextFormField(
        initialValue: _config![key]?.toString() ?? '',
        obscureText: obscure,
        decoration: adminInputDecoration(hint: hint),
        onChanged: (v) {
          _config![key] = v;
          edited();
        },
      ),
    );
  }

  /// A port box. A cleared one saves the server's default port, never 0.
  Widget _portField(String key, String label, {String? helper}) {
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'networking.$key',
      child: adminNumberInput(
        text: (_config![key] as num?)?.toString() ?? '',
        fallback: key.contains('Https') ? 8920 : 8096,
        min: 1,
        max: 65535,
        onChanged: (n) {
          _config![key] = n;
          edited();
        },
      ),
    );
  }

  Widget _switchTile(String key, String title, {String? subtitle}) {
    return adminSwitchRow(
      title: title,
      subtitle: subtitle,
      anchor: 'networking.$key',
      value: _config![key] as bool? ?? false,
      onChanged: (v) => _set(key, v),
    );
  }

  Widget _certPathField(AppLocalizations l10n) {
    const key = 'CertificatePath';
    return adminFieldRow(
      label: l10n.adminNetworkingCustomCertPath,
      helper: l10n.adminNetworkingCertPathHelp,
      anchor: 'networking.$key',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey(_certPicks),
                  initialValue: _config![key]?.toString() ?? '',
                  decoration: adminInputDecoration(),
                  onChanged: (v) {
                    _config![key] = v;
                    edited();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(_showCertBrowser ? Icons.close : Icons.folder_open),
                tooltip:
                    _showCertBrowser ? l10n.adminCloseBrowser : l10n.adminBrowse,
                onPressed: () =>
                    setState(() => _showCertBrowser = !_showCertBrowser),
              ),
            ],
          ),
          if (_showCertBrowser) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: FilesystemBrowser(
                initialPath: _config![key]?.toString(),
                // The certificate is a .pfx file, so list files too.
                includeFiles: true,
                onPathSelected: (path) {
                  _showCertBrowser = false;
                  _certPicks++;
                  _set(key, path);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterModeField(AppLocalizations l10n) {
    const key = 'IsRemoteIPFilterBlacklist';
    return adminFieldRow(
      label: l10n.adminNetworkingRemoteIpFilterMode,
      anchor: 'networking.$key',
      child: DropdownButtonFormField<bool>(
        initialValue: _config![key] as bool? ?? false,
        isExpanded: true,
        decoration: adminInputDecoration(),
        items: [
          DropdownMenuItem(
              value: false, child: Text(l10n.adminNetworkingWhitelist)),
          DropdownMenuItem(
              value: true, child: Text(l10n.adminNetworkingBlacklist)),
        ],
        onChanged: (v) => _set(key, v ?? false),
      ),
    );
  }

  Widget _listField(String key, String label, {String? helper, String? hint}) {
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'networking.$key',
      child: _listEditor(
        id: key,
        items: _strings(key),
        hint: hint,
        onChanged: (items) => _set(key, items),
      ),
    );
  }

  Widget _listEditor({
    required String id,
    required List<String> items,
    required ValueChanged<List<String>> onChanged,
    String? hint,
  }) {
    final controller =
        _listControllers.putIfAbsent(id, () => TextEditingController());
    void add() {
      final v = controller.text.trim();
      if (v.isEmpty) return;
      controller.clear();
      onChanged([...items, v]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.spaceSm,
            runSpacing: AppSpacing.spaceXs,
            children: [
              for (var i = 0; i < items.length; i++)
                Chip(
                  label: Text(items[i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12.5)),
                  onDeleted: () => onChanged([...items]..removeAt(i)),
                  backgroundColor:
                      AppColorScheme.onSurface.withValues(alpha: 0.06),
                  side: BorderSide(
                      color: AppColorScheme.onSurface.withValues(alpha: 0.10)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.spaceSm),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: adminInputDecoration(
                  hint: hint ?? AppLocalizations.of(context).adminNetworkingAddEntry,
                ),
                onSubmitted: (_) => add(),
              ),
            ),
            const SizedBox(width: AppSpacing.spaceSm),
            IconButton.filledTonal(
              tooltip: AppLocalizations.of(context).adminNetworkingAddEntry,
              icon: const Icon(Icons.add),
              onPressed: add,
            ),
          ],
        ),
      ],
    );
  }
}
