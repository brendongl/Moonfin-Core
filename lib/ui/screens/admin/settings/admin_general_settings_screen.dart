import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../admin_draft.dart';
import '../admin_nav.dart';
import '../admin_plugin_version_utils.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/filesystem_browser.dart';
import 'admin_number_input.dart';

class AdminGeneralSettingsScreen extends StatefulWidget {
  const AdminGeneralSettingsScreen({super.key});

  @override
  State<AdminGeneralSettingsScreen> createState() =>
      _AdminGeneralSettingsScreenState();
}

class _AdminGeneralSettingsScreenState
    extends State<AdminGeneralSettingsScreen>
    with AdminDraftHost {
  late final AdminSystemApi _api;
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _cultures = const [];
  List<Map<String, dynamic>> _countries = const [];
  List<Map<String, dynamic>> _localizationOptions = const [];

  /// Emby's version and platform flags, which some of its rows depend on.
  /// Empty on Jellyfin.
  Map<String, dynamic> _systemInfo = const {};
  bool _loading = true;
  String? _error;
  String? _browsingField;

  /// Bumped when the browser picks a folder, so the path field shows it.
  /// Keying on the value would rebuild the field on every keystroke.
  int _picks = 0;

  @override
  void initState() {
    super.initState();
    _api = GetIt.instance<MediaServerClient>().adminSystemApi;
    _load();
  }

  Future<void> _load() async {
    final emby = AdminServerScope.isEmby(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _api.getServerConfiguration();
      final systemInfo = emby
          ? await GetIt.instance<MediaServerClient>().systemApi
                .getSystemInfo()
                .catchError((_) => <String, dynamic>{})
          : const <String, dynamic>{};
      // Language/country lists are optional; degrade to empty on older servers.
      final cultures = await _api
          .getCultures()
          .catchError((_) => <Map<String, dynamic>>[]);
      final countries = await _api
          .getCountries()
          .catchError((_) => <Map<String, dynamic>>[]);
      final localizationOptions = await _api
          .getLocalizationOptions()
          .catchError((_) => <Map<String, dynamic>>[]);
      if (!mounted) return;
      setState(() {
        _config = config;
        _cultures = cultures;
        _countries = countries;
        _localizationOptions = localizationOptions;
        _systemInfo = systemInfo;
        _loading = false;
      });
      hostDraft(
        AdminDraft.single(
          working: config,
          reload: _api.getServerConfiguration,
          post: _api.updateServerConfiguration,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
    final config = _config!;
    final info = _systemInfo;
    final slowWarning = config['EnableSlowResponseWarning'] as bool? ?? false;
    // Each server leaves out the other's keys, so a row shows when its key
    // is there. Emby also leaves out null text fields, so its banner goes by
    // version, and some of its switches only show where the platform has them.
    final version = info['Version'];
    final bannerText = version is String &&
        compareVersionStrings(version, '4.10.0.4') >= 0;
    final performance = [
      if (config.containsKey('LibraryScanFanoutConcurrency'))
        _intField(
          'LibraryScanFanoutConcurrency',
          l10n.adminGeneralLibraryScanConcurrency,
        ),
      if (config.containsKey('ParallelImageEncodingLimit'))
        _intField(
          'ParallelImageEncodingLimit',
          l10n.adminGeneralImageEncodingLimit,
        ),
      if (config.containsKey('EnableSlowResponseWarning'))
        _switchTile(
          'EnableSlowResponseWarning',
          l10n.adminGeneralEnableSlowResponse,
        ),
      if (config.containsKey('SlowResponseThresholdMs'))
        _intField(
          'SlowResponseThresholdMs',
          l10n.adminGeneralSlowResponseThreshold,
          enabled: slowWarning,
          fallback: 500,
        ),
    ];
    final updates = [
      if (config.containsKey('EnableAutoUpdate') &&
          info['CanSelfUpdate'] == true)
        _switchTile('EnableAutoUpdate', l10n.adminGeneralAutoUpdate),
      if (config.containsKey('EnableAutomaticRestart') &&
          info['CanSelfRestart'] == true)
        _switchTile(
          'EnableAutomaticRestart',
          l10n.adminGeneralAutoRestart,
          subtitle: l10n.adminGeneralAutoRestartHelp,
        ),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminGeneralSettingsTitle,
          icon: Icons.settings_outlined,
        ),
        draftKeyed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adminSection(
                context,
                title: l10n.adminGeneralSectionServer,
                icon: Icons.dns_outlined,
                children: [
                  _textField('ServerName', l10n.adminGeneralServerName),
                  _buildDisplayLanguageDropdown(l10n),
                  if (config.containsKey('QuickConnectAvailable'))
                    _switchTile(
                      'QuickConnectAvailable',
                      l10n.adminGeneralQuickConnect,
                    ),
                  if (config.containsKey('RunAtStartup') &&
                      info['SupportsAutoRunAtStartup'] == true)
                    _switchTile('RunAtStartup', l10n.adminGeneralRunAtStartup),
                  if (config.containsKey('AutoRunWebApp') &&
                      info['CanLaunchWebBrowser'] == true)
                    _switchTile('AutoRunWebApp', l10n.adminGeneralLaunchWebApp),
                  if (bannerText)
                    _textField(
                      'BannerText',
                      l10n.adminGeneralBannerText,
                      helper: l10n.adminGeneralBannerTextHelp,
                      omitEmpty: true,
                    ),
                ],
              ),
              if (config.containsKey('IsInMaintenanceMode'))
                adminSection(
                  context,
                  title: l10n.adminGeneralSectionMaintenance,
                  icon: Icons.construction_outlined,
                  children: [
                    _switchTile(
                      'IsInMaintenanceMode',
                      l10n.adminGeneralMaintenanceMode,
                      subtitle: l10n.adminGeneralMaintenanceModeHelp,
                    ),
                    if (config['IsInMaintenanceMode'] == true)
                      _textField(
                        'MaintenanceModeMessage',
                        l10n.adminGeneralMaintenanceMessage,
                        helper: l10n.adminGeneralMaintenanceMessageHelp,
                        omitEmpty: true,
                      ),
                  ],
                ),
              adminSection(
                context,
                title: l10n.adminGeneralSectionMetadata,
                icon: Icons.language,
                children: [
                  _buildLanguageDropdown(l10n),
                  _buildCountryDropdown(l10n),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminGeneralSectionPaths,
                icon: Icons.folder_outlined,
                children: [
                  _pathField('CachePath', l10n.adminGeneralCachePath),
                  _pathField('MetadataPath', l10n.adminGeneralMetadataPath),
                ],
              ),
              if (performance.isNotEmpty)
                adminSection(
                  context,
                  title: l10n.adminGeneralSectionPerformance,
                  icon: Icons.speed,
                  children: performance,
                ),
              if (updates.isNotEmpty)
                adminSection(
                  context,
                  title: l10n.adminGeneralSectionUpdates,
                  icon: Icons.system_update_alt,
                  children: updates,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switchTile(String key, String title, {String? subtitle}) {
    return adminSwitchRow(
      title: title,
      subtitle: subtitle,
      anchor: 'settings.$key',
      value: _config![key] as bool? ?? false,
      onChanged: (v) => _set(key, v),
    );
  }

  Widget _buildLanguageDropdown(AppLocalizations l10n) {
    final current = _config!['PreferredMetadataLanguage']?.toString() ?? '';
    if (_cultures.isEmpty) {
      return _textField('PreferredMetadataLanguage',
          l10n.adminGeneralMetadataLanguage,
          hint: l10n.adminGeneralMetadataLanguageHint);
    }
    return adminCodeDropdown(
      label: l10n.adminGeneralMetadataLanguage,
      anchor: 'settings.PreferredMetadataLanguage',
      defaultLabel: l10n.adminLibDefault,
      current: current,
      rawItems: _cultures.map((c) => (
            (c['TwoLetterISOLanguageName'] ?? c['ThreeLetterISOLanguageName'])
                ?.toString(),
            (c['DisplayName'] ?? c['Name'])?.toString(),
          )),
      onChanged: (v) => _set('PreferredMetadataLanguage', v),
    );
  }

  Widget _buildDisplayLanguageDropdown(AppLocalizations l10n) {
    final current = _config!['UICulture']?.toString() ?? '';
    if (_localizationOptions.isEmpty) {
      return _textField('UICulture', l10n.adminGeneralDisplayLanguage);
    }
    return adminCodeDropdown(
      label: l10n.adminGeneralDisplayLanguage,
      anchor: 'settings.UICulture',
      defaultLabel: l10n.adminLibDefault,
      current: current,
      rawItems: _localizationOptions.map((o) => (
            o['Value']?.toString(),
            (o['Name'] ?? o['Value'])?.toString(),
          )),
      onChanged: (v) => _set('UICulture', v),
    );
  }

  Widget _buildCountryDropdown(AppLocalizations l10n) {
    final current = _config!['MetadataCountryCode']?.toString() ?? '';
    if (_countries.isEmpty) {
      return _textField('MetadataCountryCode', l10n.adminGeneralMetadataCountry,
          hint: l10n.adminGeneralMetadataCountryHint);
    }
    return adminCodeDropdown(
      label: l10n.adminGeneralMetadataCountry,
      anchor: 'settings.MetadataCountryCode',
      defaultLabel: l10n.adminLibDefault,
      current: current,
      rawItems: _countries.map((c) => (
            (c['TwoLetterISORegionName'] ?? c['Name'])?.toString(),
            (c['DisplayName'] ?? c['Name'])?.toString(),
          )),
      onChanged: (v) => _set('MetadataCountryCode', v),
    );
  }

  /// With [omitEmpty] a cleared box drops the key, so Emby stores null and
  /// falls back to its default.
  Widget _textField(
    String key,
    String label, {
    String? hint,
    String? helper,
    bool omitEmpty = false,
  }) {
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'settings.$key',
      child: TextFormField(
        initialValue: _config![key]?.toString() ?? '',
        decoration: adminInputDecoration(hint: hint),
        onChanged: (v) {
          if (omitEmpty && v.isEmpty) {
            _config!.remove(key);
          } else {
            _config![key] = v;
          }
          edited();
        },
      ),
    );
  }

  /// A cleared box saves [fallback], the server's default.
  Widget _intField(
    String key,
    String label, {
    bool enabled = true,
    int fallback = 0,
  }) {
    return adminFieldRow(
      label: label,
      anchor: 'settings.$key',
      child: adminNumberInput(
        text: (_config![key] as num?)?.toString() ?? '',
        fallback: fallback,
        enabled: enabled,
        onChanged: (n) {
          _config![key] = n;
          edited();
        },
      ),
    );
  }

  Widget _pathField(String key, String label) {
    final l10n = AppLocalizations.of(context);
    final isBrowsing = _browsingField == key;
    return adminFieldRow(
      label: label,
      anchor: 'settings.$key',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('$key-$_picks'),
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
                icon: Icon(isBrowsing ? Icons.close : Icons.folder_open),
                tooltip: isBrowsing ? l10n.adminCloseBrowser : l10n.adminBrowse,
                onPressed: () => setState(() {
                  _browsingField = isBrowsing ? null : key;
                }),
              ),
            ],
          ),
          if (isBrowsing) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: FilesystemBrowser(
                initialPath: _config![key]?.toString(),
                validateWritable: true,
                onPathSelected: (path) {
                  _browsingField = null;
                  _picks++;
                  _set(key, path);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
