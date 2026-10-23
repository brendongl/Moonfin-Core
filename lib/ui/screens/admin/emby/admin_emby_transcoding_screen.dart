import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/emby_premiere_dialog.dart';
import '../admin_draft.dart';
import '../admin_search_index.dart';
import '../providers/admin_status_providers.dart';
import '../settings/admin_number_input.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/premiere_note.dart';
import 'admin_config_form.dart';

AdminSearchEntry _hwa(String key, L10nText label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminPlaybackHwAccel);
AdminSearchEntry _main(String key, L10nText label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminDrawerTranscoding);
AdminSearchEntry _tone(String key, L10nText label) => adminSettingRow(
  'transcoding',
  key,
  label,
  (l) => l.adminPlaybackToneMapping,
);

final List<AdminSearchEntry> embyTranscodingSearchEntries = [
  _hwa('HardwareAccelerationMode', (l) => l.adminPlaybackHwAccelLabel),
  _main('TranscodingTempPath', (l) => l.adminPlaybackTranscodeTempPath),
  _main('EnableThrottling', (l) => l.adminPlaybackThrottleBuffering),
  _main('DownMixAudioBoost', (l) => l.adminPlaybackDownmixBoost),
  _main(
    'EnableSubtitleExtraction',
    (l) => l.adminPlaybackEnableSubtitleExtraction,
  ),
  _main(
    'EnableOnTheFlyAttachmentExtraction',
    (l) => l.adminTranscodingFontExtraction,
  ),
  _main('EnableHevcEncoding', (l) => l.adminPlaybackAllowHevcEncoding),
  _main('TranscodingMaxWidth', (l) => l.adminTranscodingMaxResolution),
  _tone('EnableSoftwareToneMapping', (l) => l.adminTranscodingToneMapSoftware),
  _tone('EnableHardwareToneMapping', (l) => l.adminTranscodingToneMapHardware),
];

/// Emby's `encoding` configuration, which has its own shape: a hardware
/// acceleration mode and, in Advanced mode, a priority list of the hardware
/// codecs the server found.
class AdminEmbyTranscodingScreen extends ConsumerStatefulWidget {
  const AdminEmbyTranscodingScreen({super.key});

  @override
  ConsumerState<AdminEmbyTranscodingScreen> createState() =>
      _AdminEmbyTranscodingScreenState();
}

class _AdminEmbyTranscodingScreenState
    extends ConsumerState<AdminEmbyTranscodingScreen>
    with AdminDraftHost {
  static const _advanced = 2;

  final _client = GetIt.instance<MediaServerClient>();
  Map<String, dynamic>? _config;
  String? _error;
  List<Map<String, dynamic>> _codecs = const [];
  Map<String, dynamic> _toneMap = const {};
  bool _hwaNeedsPremiere = false;
  // Re-keys the mode dropdown when the Premiere dialog turns a pick down.
  int _modeResets = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _fetch() =>
      _client.adminSystemApi.getNamedConfiguration('encoding');

  Future<void> _load() async {
    setState(() => _error = null);
    final emby = _client.embyAdminApi!;
    try {
      final results = await Future.wait<Object>([
        _fetch(),
        emby.getVideoCodecInformation().catchError(
          (_) => <Map<String, dynamic>>[],
        ),
        emby.getToneMapOptions().catchError((_) => <String, dynamic>{}),
        _client.systemApi.getSystemInfo(),
      ]);
      if (!mounted) return;
      final config = results[0] as Map<String, dynamic>;
      _codecs = [
        for (final codec in results[1] as List<Map<String, dynamic>>)
          if (codec['IsHardwareCodec'] == true) codec,
      ];
      _toneMap =
          (results[2] as Map<String, dynamic>)['Object']
              as Map<String, dynamic>? ??
          const {};
      _hwaNeedsPremiere = SystemInfo.fromJson(
        results[3] as Map<String, dynamic>,
      ).hardwareAccelerationRequiresPremiere;
      if (config['HardwareAccelerationMode'] == _advanced) _fillCodecs(config);
      setState(() => _config = config);
      hostDraft(
        AdminDraft.single(
          working: config,
          reload: _fetch,
          post: (value) => _client.adminSystemApi.updateNamedConfiguration(
            'encoding',
            value,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, AppLocalizations.of(context)));
    }
  }

  void _set(String key, Object? value) {
    setState(() => _config![key] = value);
    edited();
  }

  /// Gives every hardware codec an entry. A fresh list starts from the
  /// server's defaults, as Yes mode uses them, and a codec the list doesn't
  /// know yet starts off.
  void _fillCodecs(Map<String, dynamic> config) {
    final list = [
      for (final e in config['CodecConfigurations'] as List? ?? const [])
        Map<String, dynamic>.from(e as Map),
    ];
    final fresh = list.isEmpty;
    for (final codec in _codecs) {
      if (list.any((e) => e['CodecId'] == codec['Id'])) continue;
      list.add({
        'CodecId': codec['Id'],
        'Priority': fresh ? codec['DefaultPriority'] ?? 0 : 0,
        'IsEnabled': fresh && codec['IsEnabledByDefault'] == true,
      });
    }
    config['CodecConfigurations'] = list;
  }

  /// Whether to go on turning on a feature Premiere gates.
  Future<bool> _premiereOk(bool gated) async {
    if (!gated) return true;
    final status = await ref.read(premiereStatusProvider.future);
    if (!mounted) return false;
    if (status == null || status.isActive) return true;
    return showPremiereRequiredDialog(context, saving: true);
  }

  Future<void> _setMode(int? mode) async {
    final was = (_config!['HardwareAccelerationMode'] as num?)?.toInt() ?? 0;
    if (mode == null || mode == was) return;
    if (was == 0 && !await _premiereOk(_hwaNeedsPremiere)) {
      if (mounted) setState(() => _modeResets++);
      return;
    }
    if (!mounted) return;
    _config!['HardwareAccelerationMode'] = mode;
    // Only Advanced mode keeps a list, the others use the defaults.
    if (mode == _advanced) {
      _fillCodecs(_config!);
    } else {
      _config!['CodecConfigurations'] = <Object>[];
    }
    setState(() {});
    edited();
  }

  Widget _toggle(
    String key,
    String title, {
    String? help,
    bool premiere = false,
  }) => adminSwitchRow(
    title: title,
    subtitle: help,
    anchor: 'transcoding.$key',
    value: _config![key] == true,
    onChanged: (v) async {
      if (v && !await _premiereOk(premiere)) return;
      if (mounted) _set(key, v);
    },
  );

  Widget _dropdown(
    String key,
    List<(int, String)> options,
    ValueChanged<int?> onChanged, {
    Key? fieldKey,
  }) => adminChoiceDropdown(
    key: fieldKey,
    value: (_config![key] as num?)?.toInt() ?? 0,
    options: options,
    onChanged: onChanged,
  );

  /// The hardware codecs going [direction], by media type and then priority.
  List<Widget> _codecRows(AppLocalizations l10n, String direction) {
    final configs = (_config!['CodecConfigurations'] as List)
        .cast<Map<String, dynamic>>();
    num priority(Map<String, dynamic> e) => e['Priority'] as num? ?? 0;
    final rows =
        <(Map<String, dynamic>, Map<String, dynamic>)>[
          for (final codec in _codecs)
            if (codec['Direction'] == direction)
              if (configs.firstWhereOrNull((e) => e['CodecId'] == codec['Id'])
                  case final entry?)
                (codec, entry),
        ]..sort((a, b) {
          final byType = '${a.$1['MediaTypeName']}'.compareTo(
            '${b.$1['MediaTypeName']}',
          );
          return byType != 0
              ? byType
              : priority(b.$2).compareTo(priority(a.$2));
        });

    // Priority only ranks codecs for the same media type, so a codec swaps
    // within its type and the type is renumbered from the top.
    void move(int from, int to) {
      final type = rows[from].$1['MediaTypeName'];
      final group = [
        for (final (codec, entry) in rows)
          if (codec['MediaTypeName'] == type) entry,
      ];
      final a = group.indexOf(rows[from].$2);
      final b = group.indexOf(rows[to].$2);
      group[a] = rows[to].$2;
      group[b] = rows[from].$2;
      for (var i = 0; i < group.length; i++) {
        group[i]['Priority'] = 100 - i;
      }
      setState(() {});
      edited();
    }

    bool sameType(int i, int j) =>
        j >= 0 &&
        j < rows.length &&
        rows[i].$1['MediaTypeName'] == rows[j].$1['MediaTypeName'];

    return [
      for (var i = 0; i < rows.length; i++)
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: rows[i].$2['IsEnabled'] == true,
          title: Text('${rows[i].$1['Name']}'),
          subtitle: Text('${rows[i].$1['MediaTypeName']}'),
          onChanged: (v) {
            setState(() => rows[i].$2['IsEnabled'] = v ?? false);
            edited();
          },
          secondary: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: l10n.moveUp,
                onPressed: sameType(i, i - 1) ? () => move(i, i - 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                tooltip: l10n.moveDown,
                onPressed: sameType(i, i + 1) ? () => move(i, i + 1) : null,
              ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Keeps the license status loaded for _premiereOk.
    ref.watch(premiereStatusProvider);
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.adminPlaybackLoadFailed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (_config == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final advanced = _config!['HardwareAccelerationMode'] == _advanced;
    final visibility = _toneMap['OptionsVisibility'] as Map? ?? const {};
    final softwareToneMap =
        visibility['IsSoftwareToneMappingAvailable'] == true;
    final hardwareToneMap =
        visibility['IsAnyHardwareToneMappingAvailable'] == true;
    final toneMapPremiere = _toneMap['FeatureRequiresPremiere'] == true;

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
          title: l10n.adminDrawerTranscoding,
          icon: Icons.swap_horiz,
        ),
        draftKeyed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adminSection(
                context,
                title: l10n.adminPlaybackHwAccel,
                icon: Icons.memory,
                children: [
                  adminFieldRow(
                    label: l10n.adminPlaybackHwAccelLabel,
                    helper: l10n.adminTranscodingHwaHelp,
                    anchor: 'transcoding.HardwareAccelerationMode',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _dropdown(
                          'HardwareAccelerationMode',
                          [
                            (0, l10n.no),
                            (1, l10n.yes),
                            (_advanced, l10n.adminTranscodingHwaAdvanced),
                          ],
                          _setMode,
                          fieldKey: ValueKey(_modeResets),
                        ),
                        if (_hwaNeedsPremiere)
                          const PremiereNote(margin: EdgeInsets.only(top: 8)),
                      ],
                    ),
                  ),
                ],
              ),
              if (advanced)
                for (final (direction, title, icon) in [
                  ('Decoder', l10n.adminTranscodingHwDecoders, Icons.input),
                  ('Encoder', l10n.adminTranscodingHwEncoders, Icons.output),
                ])
                  if (_codecRows(l10n, direction) case final rows
                      when rows.isNotEmpty)
                    adminSection(
                      context,
                      title: title,
                      icon: icon,
                      children: rows,
                    ),
              adminSection(
                context,
                title: l10n.adminDrawerTranscoding,
                icon: Icons.movie_filter_outlined,
                children: [
                  adminFieldRow(
                    label: l10n.adminPlaybackTranscodeTempPath,
                    helper: l10n.adminTranscodingTempPathHelp,
                    anchor: 'transcoding.TranscodingTempPath',
                    child: AdminPathInput(
                      value: _config!['TranscodingTempPath'] as String?,
                      onChanged: (v) => _set('TranscodingTempPath', v),
                    ),
                  ),
                  _toggle(
                    'EnableThrottling',
                    l10n.adminPlaybackThrottleBuffering,
                    help: l10n.adminTranscodingThrottleHelp,
                  ),
                  adminFieldRow(
                    label: l10n.adminPlaybackDownmixBoost,
                    helper: l10n.adminTranscodingDownmixHelp,
                    anchor: 'transcoding.DownMixAudioBoost',
                    child: adminNumberInput(
                      text: '${_config!['DownMixAudioBoost'] ?? ''}',
                      fallback: 1,
                      min: 0.5,
                      max: 3,
                      decimal: true,
                      onChanged: (n) => _set('DownMixAudioBoost', n),
                    ),
                  ),
                  _toggle(
                    'EnableSubtitleExtraction',
                    l10n.adminPlaybackEnableSubtitleExtraction,
                  ),
                  _toggle(
                    'EnableOnTheFlyAttachmentExtraction',
                    l10n.adminTranscodingFontExtraction,
                  ),
                  _toggle(
                    'EnableHevcEncoding',
                    l10n.adminPlaybackAllowHevcEncoding,
                  ),
                  adminFieldRow(
                    label: l10n.adminTranscodingMaxResolution,
                    helper: l10n.adminTranscodingMaxResolutionHelp,
                    anchor: 'transcoding.TranscodingMaxWidth',
                    child: _dropdown('TranscodingMaxWidth', [
                      (0, l10n.noLimit),
                      (3840, '4K'),
                      (1920, '1080p'),
                      (1280, '720p'),
                      (720, '480p'),
                    ], (v) => _set('TranscodingMaxWidth', v)),
                  ),
                ],
              ),
              // Emby keeps these two flags in the encoding configuration too.
              if (softwareToneMap || hardwareToneMap) ...[
                adminSection(
                  context,
                  title: l10n.adminPlaybackToneMapping,
                  icon: Icons.hdr_on_outlined,
                  children: [
                    if (softwareToneMap)
                      _toggle(
                        'EnableSoftwareToneMapping',
                        l10n.adminTranscodingToneMapSoftware,
                        help: l10n.adminTranscodingToneMapHelp,
                        premiere: toneMapPremiere,
                      ),
                    if (hardwareToneMap)
                      _toggle(
                        'EnableHardwareToneMapping',
                        l10n.adminTranscodingToneMapHardware,
                        help: softwareToneMap
                            ? null
                            : l10n.adminTranscodingToneMapHelp,
                        premiere: toneMapPremiere,
                      ),
                  ],
                ),
                if (toneMapPremiere)
                  const PremiereNote(margin: EdgeInsets.only(top: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
