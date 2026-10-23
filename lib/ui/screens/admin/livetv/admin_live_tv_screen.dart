import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../util/platform_detection.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../../detail/modern/widgets/details_tab_bar.dart';
import '../admin_draft.dart';
import '../admin_nav.dart';
import '../providers/admin_user_providers.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/admin_settings_search.dart';
import '../widgets/premiere_note.dart';
import 'live_tv_dialogs.dart';

/// Live TV in two tabs: tuners and guide providers, which save at once, and
/// recording settings, a draft over the named configuration 'livetv'.
class AdminLiveTvScreen extends StatefulWidget {
  const AdminLiveTvScreen({super.key});

  @override
  State<AdminLiveTvScreen> createState() => _AdminLiveTvScreenState();
}

class _AdminLiveTvScreenState extends State<AdminLiveTvScreen>
    with AdminDraftHost {
  bool _loading = true;
  bool _discovering = false;
  bool _refreshingGuide = false;
  String? _error;
  int _tab = 0;
  int _browsed = 0;
  final _tabNodes = <int, FocusNode>{};

  /// The draft's working copy of 'livetv', edited by the Recordings tab.
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _tuners = const [];
  List<Map<String, dynamic>> _providers = const [];
  List<Map<String, dynamic>> _discovered = const [];

  /// The guide sources Add offers. Emby lists its own.
  List<String> _guideSources = const ['SchedulesDirect', 'xmltv'];

  AdminLiveTvApi get _api => GetIt.instance<MediaServerClient>().adminLiveTvApi;

  EmbyAdminApi? get _emby => AdminServerScope.isEmby(context)
      ? GetIt.instance<MediaServerClient>().embyAdminApi
      : null;

  @override
  void initState() {
    super.initState();
    AdminSettingAnchor.pending.addListener(_onSearch);
    _load();
  }

  @override
  void dispose() {
    AdminSettingAnchor.pending.removeListener(_onSearch);
    for (final node in _tabNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _tabNode(int index) => _tabNodes.putIfAbsent(
      index, () => FocusNode(debugLabel: 'admin_live_tv_tab_$index'));

  /// Only the Recordings rows and the two lists carry anchors.
  static int? _tabFor(String? anchor) {
    if (anchor == null || !anchor.startsWith('live-tv.')) return null;
    return anchor == 'live-tv.TunerHosts' ||
            anchor == 'live-tv.ListingProviders'
        ? 0
        : 1;
  }

  /// A search result on the other tab switches to it before the row reveals.
  void _onSearch() {
    final tab = _tabFor(AdminSettingAnchor.pending.value);
    if (tab != null && tab != _tab && mounted) setState(() => _tab = tab);
  }

  void _setLists(Map<String, dynamic> config) {
    _tuners = liveTvMaps(config['TunerHosts']);
    _providers = liveTvMaps(config['ListingProviders']);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _api.getLiveTvConfiguration();
      final sources = await _emby
          ?.getAvailableListingProviders()
          .catchError((_) => [<String, dynamic>{'Id': 'xmltv'}]);
      if (!mounted) return;
      setState(() {
        _config = config;
        _setLists(config);
        if (sources != null) {
          // Only the sources this page has a form for.
          _guideSources = [
            for (final s in sources)
              if (const {'xmltv', 'embygn'}.contains(s['Id'])) s['Id'] as String,
          ];
        }
        _tab = _tabFor(AdminSettingAnchor.pending.value) ?? _tab;
        _loading = false;
      });
      hostDraft(
        AdminDraft.single(
          working: config,
          reload: _api.getLiveTvConfiguration,
          post: _api.updateLiveTvConfiguration,
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

  /// Re-reads the lists after an immediate action. The draft keeps its own
  /// copy, and its save reloads the object anyway.
  Future<void> _refreshLists() async {
    try {
      final config = await _api.getLiveTvConfiguration();
      if (mounted) setState(() => _setLists(config));
    } catch (e) {
      if (mounted) _snack(describeError(e, AppLocalizations.of(context)));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirmDelete(String title, String message) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(title),
        content: Text(message),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          adaptiveDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<List<(String, String)>> _loadTunerTypes() async {
    final l10n = AppLocalizations.of(context);
    try {
      final types = [
        for (final t in await _api.getTunerHostTypes())
          if ((t['Id']?.toString() ?? '').isNotEmpty)
            (t['Id'].toString(), t['Name']?.toString() ?? t['Id'].toString()),
      ];
      if (types.isNotEmpty) return types;
    } catch (_) {}
    return [
      ('m3u', l10n.adminTunerTypeM3u),
      ('hdhomerun', l10n.adminTunerTypeHdHomerun),
    ];
  }

  Future<void> _editTuner([Map<String, dynamic> seed = const {}]) async {
    final types = await _loadTunerTypes();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => LiveTvTunerDialog(
        api: _api,
        types: types,
        seed: seed,
        emby: AdminServerScope.isEmby(context),
      ),
    );
    if (saved != true || !mounted) return;
    _snack(AppLocalizations.of(context).adminLiveTvTunerSaved);
    setState(() => _discovered = [
          for (final d in _discovered)
            if (!identical(d, seed)) d,
        ]);
    await _refreshLists();
  }

  Future<void> _deleteTuner(Map<String, dynamic> tuner) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirmDelete(
      l10n.adminLiveTvDeleteTuner,
      l10n.adminLiveTvDeleteTunerConfirm,
    )) {
      return;
    }
    try {
      await _api.removeTunerHost(tuner['Id'].toString());
      await _refreshLists();
    } catch (e) {
      _snack(l10n.adminTunerRemoveFailed(describeError(e, l10n)));
    }
  }

  Future<void> _discover() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _discovering = true);
    try {
      final found = await _api.discoverTuners();
      if (!mounted) return;
      setState(() => _discovered = found);
      if (found.isEmpty) _snack(l10n.adminLiveTvNoNewDevices);
    } catch (e) {
      _snack(l10n.adminTunerDiscoveryFailed(describeError(e, l10n)));
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  /// The name of a guide source type, null for one this page can't edit.
  static String? _sourceName(String type, AppLocalizations l10n) =>
      switch (type.toLowerCase()) {
        'xmltv' => l10n.adminProviderXmltv,
        'schedulesdirect' => l10n.adminProviderSchedulesDirect,
        'embygn' => l10n.adminProviderEmbyGuide,
        _ => null,
      };

  /// [type] is 'xmltv', 'SchedulesDirect' or Emby's 'embygn'. A new XMLTV
  /// provider starts from the server's default.
  Future<void> _editProvider(
    String type, [
    Map<String, dynamic>? stored,
  ]) async {
    final l10n = AppLocalizations.of(context);
    final xmltv = type.toLowerCase() == 'xmltv';
    var seed = stored ?? const <String, dynamic>{};
    if (xmltv && stored == null) {
      try {
        seed = await _api.getDefaultListingProvider();
      } catch (e) {
        _snack(describeError(e, l10n));
        return;
      }
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => xmltv
          ? LiveTvXmltvDialog(api: _api, seed: seed, tuners: _tuners)
          : LiveTvSchedulesDirectDialog(
              api: _api,
              seed: seed,
              tuners: _tuners,
              embyGuide: type.toLowerCase() == 'embygn',
            ),
    );
    if (saved != true || !mounted) return;
    _snack(l10n.adminLiveTvProviderSaved);
    await _refreshLists();
  }

  Future<void> _deleteProvider(Map<String, dynamic> provider) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirmDelete(
      l10n.adminLiveTvDeleteProvider,
      l10n.adminLiveTvDeleteProviderConfirm,
    )) {
      return;
    }
    try {
      await _api.removeListingProvider(provider['Id'].toString());
      await _refreshLists();
    } catch (e) {
      _snack(l10n.adminProviderRemoveFailed(describeError(e, l10n)));
    }
  }

  Future<void> _mapChannels(Map<String, dynamic> provider) => showDialog(
        context: context,
        builder: (_) => LiveTvChannelMapperDialog(
          api: _api,
          providerId: provider['Id'].toString(),
          emby: _emby,
        ),
      );

  TaskInfo? _guideTask(WidgetRef ref) => ref
      .watch(adminTasksProvider)
      .valueOrNull
      ?.where((t) => t.key == 'RefreshGuide')
      .firstOrNull;

  Future<void> _refreshGuide() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _refreshingGuide = true);
    try {
      final tasksApi = GetIt.instance<MediaServerClient>().adminTasksApi;
      // Visible tasks only, since the server hides this one while no tuner is
      // set up.
      final tasks = await tasksApi.getTasks(isHidden: false);
      final id = tasks
              .firstWhere(
                (t) => t['Key'] == 'RefreshGuide',
                orElse: () => const <String, dynamic>{},
              )['Id']
              ?.toString() ??
          '';
      if (id.isEmpty) {
        _snack(l10n.adminGuideRefreshUnavailable);
        return;
      }
      await tasksApi.startTask(id);
      _snack(l10n.adminGuideRefreshStarted);
    } catch (e) {
      _snack(describeError(e, l10n));
    } finally {
      if (mounted) setState(() => _refreshingGuide = false);
    }
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
            Text(l10n.adminLiveTvLoadFailed,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error ?? l10n.adminUnknownError,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminDrawerLiveTv,
          icon: Icons.live_tv,
        ),
        PremiereNote(message: (l) => l.adminPremiereNoteLiveTv),
        DetailsTabBar(
          segmented: true,
          wrap: PlatformDetection.useMobileUi,
          labels: [l10n.adminLiveTvTabSources, l10n.adminLiveTvTabRecordings],
          selectedIndex: _tab,
          onSelect: (i) => setState(() => _tab = i),
          focusNodeFor: _tabNode,
        ),
        if (_tab == 0) ..._sourcesTab(l10n) else _recordingsTab(l10n),
      ],
    );
  }

  Widget? _subtitle(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : Text(text);
  }

  Widget _actionRow(List<Widget> buttons) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
      );

  List<Widget> _sourcesTab(AppLocalizations l10n) {
    return [
      adminSectionLabel(
        context,
        l10n.adminTunerDevices,
        icon: Icons.settings_input_antenna,
      ),
      AdminSettingAnchor(
        id: 'live-tv.TunerHosts',
        child: adminGlassGroup(
          context,
          children: [
            if (_tuners.isEmpty) ListTile(title: Text(l10n.adminNoTunerHosts)),
            for (final tuner in _tuners)
              ListTile(
                leading: const Icon(Icons.dvr),
                title: Text(liveTvTunerName(tuner, l10n)),
                subtitle: _subtitle(tuner['Url']),
                onTap: () => _editTuner(tuner),
                trailing: IconButton(
                  tooltip: l10n.delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteTuner(tuner),
                ),
              ),
            for (final device in _discovered)
              ListTile(
                leading: const Icon(Icons.radar),
                title: Text(liveTvTunerName(device, l10n)),
                subtitle: _subtitle(device['Url']),
                trailing: FilledButton.tonal(
                  onPressed: () => _editTuner(device),
                  child: Text(l10n.add),
                ),
              ),
            _actionRow([
              FilledButton.tonalIcon(
                onPressed: _editTuner,
                icon: const Icon(Icons.add),
                label: Text(l10n.adminLiveTvAddTuner),
              ),
              OutlinedButton.icon(
                onPressed: _discovering ? null : _discover,
                icon: _discovering ? liveTvSpinner() : const Icon(Icons.radar),
                label: Text(l10n.adminLiveTvDetectDevices),
              ),
            ]),
          ],
        ),
      ),
      adminSectionLabel(
        context,
        l10n.adminGuideProviders,
        icon: Icons.event_note_outlined,
      ),
      AdminSettingAnchor(
        id: 'live-tv.ListingProviders',
        child: adminGlassGroup(
          context,
          children: [
            if (_providers.isEmpty)
              ListTile(title: Text(l10n.adminNoListingProviders)),
            for (final provider in _providers) _providerTile(provider, l10n),
            _actionRow([
              MenuAnchor(
                menuChildren: [
                  for (final type in _guideSources)
                    MenuItemButton(
                      onPressed: () => _editProvider(type),
                      child: Text(_sourceName(type, l10n)!),
                    ),
                ],
                builder: (context, menu, _) => FilledButton.tonalIcon(
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.adminLiveTvAddProvider),
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final busy = _refreshingGuide ||
                      _guideTask(ref)?.state == 'Running';
                  return OutlinedButton.icon(
                    onPressed: busy ? null : _refreshGuide,
                    icon: busy ? liveTvSpinner() : const Icon(Icons.refresh),
                    label: Text(l10n.adminLiveTvRefreshGuide),
                  );
                },
              ),
            ]),
            Consumer(
              builder: (context, ref, _) {
                final task = _guideTask(ref);
                if (task?.state != 'Running') return const SizedBox.shrink();
                final pct = task!.currentProgressPercentage;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    value: pct == null ? null : pct / 100,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ];
  }

  Widget _providerTile(Map<String, dynamic> provider, AppLocalizations l10n) {
    final type = provider['Type']?.toString() ?? '';
    final name = _sourceName(type, l10n);
    final path = provider['Path']?.toString() ?? '';
    return ListTile(
      leading: const Icon(Icons.event_note_outlined),
      title: Text(name ?? (type.isEmpty ? l10n.unknown : type)),
      subtitle: _subtitle(path.isEmpty ? provider['ListingsId'] : path),
      onTap: name == null ? null : () => _editProvider(type, provider),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.adminLiveTvMapChannels,
            icon: const Icon(Icons.location_searching),
            onPressed: () => _mapChannels(provider),
          ),
          IconButton(
            tooltip: l10n.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteProvider(provider),
          ),
        ],
      ),
    );
  }

  void _set(String key, Object? value) {
    setState(() => _config![key] = value);
    edited();
  }

  void _put(String key, Object? value) {
    _config![key] = value;
    edited();
  }

  Widget _recordingsTab(AppLocalizations l10n) {
    return draftKeyed(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          adminSection(
            context,
            title: l10n.adminLiveTvSectionGuide,
            icon: Icons.calendar_month_outlined,
            children: [
              _guideDaysRow(l10n),
              if (_config!.containsKey('WakeServer'))
                _switchRow('WakeServer', l10n.adminLiveTvWakeServer),
            ],
          ),
          adminSection(
            context,
            title: l10n.adminLiveTvSectionPaths,
            icon: Icons.folder_outlined,
            children: [
              _pathRow(
                'RecordingPath',
                l10n.adminLiveTvRecordingPath,
                helper: l10n.adminLiveTvRecordingPathHelp,
              ),
              _pathRow('MovieRecordingPath', l10n.adminMovieRecordingPath),
              _pathRow('SeriesRecordingPath', l10n.adminSeriesRecordingPath),
            ],
          ),
          adminSection(
            context,
            title: l10n.adminLiveTvSectionDefaultRecording,
            icon: Icons.timer_outlined,
            children: [
              _paddingRow(
                'PrePaddingSeconds',
                l10n.adminLiveTvStartWhenPossible,
                l10n.adminLiveTvMinutesBefore,
              ),
              _paddingRow(
                'PostPaddingSeconds',
                l10n.adminLiveTvStopWhenPossible,
                l10n.adminLiveTvMinutesAfter,
              ),
            ],
          ),
          adminSection(
            context,
            title: l10n.adminLiveTvSectionPostProcessing,
            icon: Icons.terminal,
            children: [
              _pathRow(
                'RecordingPostProcessor',
                l10n.adminRecordingPostProcessor,
                files: true,
              ),
              adminFieldRow(
                label: l10n.adminRecordingPostProcessorArgs,
                anchor: 'live-tv.RecordingPostProcessorArguments',
                child: TextFormField(
                  initialValue:
                      _config!['RecordingPostProcessorArguments']?.toString() ??
                          '',
                  decoration: adminInputDecoration(),
                  onChanged: (v) => _put('RecordingPostProcessorArguments', v),
                ),
              ),
            ],
          ),
          // Emby has neither.
          if (_config!.containsKey('SaveRecordingNFO'))
            adminSection(
              context,
              title: l10n.adminLiveTvSectionMetadata,
              icon: Icons.description_outlined,
              children: [
                _switchRow('SaveRecordingNFO', l10n.adminSaveRecordingNfo),
                _switchRow('SaveRecordingImages', l10n.adminSaveRecordingImages),
              ],
            ),
        ],
      ),
    );
  }

  Widget _guideDaysRow(AppLocalizations l10n) {
    final days = (_config!['GuideDays'] as num?)?.toInt();
    return adminFieldRow(
      label: l10n.adminLiveTvGuideDays,
      helper: l10n.adminLiveTvGuideDaysHelp,
      anchor: 'live-tv.GuideDays',
      child: DropdownButtonFormField<int?>(
        initialValue: days,
        isExpanded: true,
        decoration: adminInputDecoration(),
        items: [
          DropdownMenuItem(value: null, child: Text(l10n.adminGuideDaysAuto)),
          for (var d = 1; d <= 14; d++)
            DropdownMenuItem(value: d, child: Text('$d')),
          // Keeps a stored value outside 1 to 14 listed.
          if (days != null && (days < 1 || days > 14))
            DropdownMenuItem(value: days, child: Text('$days')),
        ],
        onChanged: (v) => _set('GuideDays', v),
      ),
    );
  }

  Widget _pathRow(
    String key,
    String label, {
    String? helper,
    bool files = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'live-tv.$key',
      child: TextFormField(
        // Re-keyed only when a browse result lands, so typing keeps focus.
        key: ValueKey('$key#$_browsed'),
        initialValue: _config![key]?.toString() ?? '',
        decoration: adminInputDecoration(
          suffixIcon: IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: l10n.adminBrowse,
            onPressed: () async {
              final path = await pickServerPath(
                context,
                initial: files ? null : _config![key]?.toString(),
                files: files,
                writable: !files,
              );
              if (path == null || !mounted) return;
              _browsed++;
              _set(key, path);
            },
          ),
        ),
        onChanged: (v) => _put(key, v),
      ),
    );
  }

  /// Minutes on screen, seconds on the server, with no rounding to whole
  /// minutes.
  Widget _paddingRow(String key, String label, String suffix) {
    final seconds = (_config![key] as num?)?.toInt() ?? 0;
    return adminFieldRow(
      label: label,
      anchor: 'live-tv.$key',
      child: TextFormField(
        initialValue:
            seconds % 60 == 0 ? '${seconds ~/ 60}' : '${seconds / 60}',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: adminInputDecoration(suffixText: suffix),
        onChanged: (v) =>
            _put(key, ((double.tryParse(v.trim()) ?? 0) * 60).round()),
      ),
    );
  }

  Widget _switchRow(String key, String title) => adminSwitchRow(
        title: title,
        anchor: 'live-tv.$key',
        value: _config![key] as bool? ?? true,
        onChanged: (v) => _set(key, v),
      );
}
