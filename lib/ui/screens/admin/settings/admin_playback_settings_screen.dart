import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../admin_draft.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/filesystem_browser.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import 'admin_number_input.dart';

class AdminPlaybackSettingsScreen extends StatefulWidget {
  const AdminPlaybackSettingsScreen({super.key});

  @override
  State<AdminPlaybackSettingsScreen> createState() =>
      _AdminPlaybackSettingsScreenState();
}

class _AdminPlaybackSettingsScreenState
    extends State<AdminPlaybackSettingsScreen>
    with AdminDraftHost {
  late final AdminSystemApi _api;
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;
  String? _browsingField;
  // Bumped when the folder browser picks a path, so its field shows it.
  int _picks = 0;

  // 'none' is localized at build.
  static const _hwAccelOptions = [
    ('none', ''),
    ('amf', 'AMD AMF'),
    ('nvenc', 'Nvidia NVENC'),
    ('qsv', 'Intel Quicksync (QSV)'),
    ('vaapi', 'Video Acceleration API (VAAPI)'),
    ('rkmpp', 'Rockchip MPP (RKMPP)'),
    ('videotoolbox', 'Apple VideoToolBox'),
    ('v4l2m2m', 'Video4Linux2 (V4L2)'),
  ];

  // Each codec and the hardware types that can decode it.
  static const _hwDecodeCodecs = [
    ('h264', 'H.264', ['amf', 'nvenc', 'qsv', 'vaapi', 'rkmpp', 'videotoolbox', 'v4l2m2m']),
    ('hevc', 'HEVC', ['amf', 'nvenc', 'qsv', 'vaapi', 'rkmpp', 'videotoolbox']),
    ('mpeg1video', 'MPEG-1', ['rkmpp']),
    ('mpeg2video', 'MPEG-2', ['amf', 'nvenc', 'qsv', 'vaapi', 'rkmpp']),
    ('mpeg4', 'MPEG-4', ['nvenc', 'rkmpp']),
    ('vc1', 'VC-1', ['amf', 'nvenc', 'qsv', 'vaapi']),
    ('vp8', 'VP8', ['nvenc', 'qsv', 'vaapi', 'rkmpp', 'videotoolbox']),
    ('vp9', 'VP9', ['amf', 'nvenc', 'qsv', 'vaapi', 'rkmpp', 'videotoolbox']),
    ('av1', 'AV1', ['amf', 'nvenc', 'qsv', 'vaapi', 'rkmpp', 'videotoolbox']),
  ];
  static const _tenBitTypes = ['amf', 'nvenc', 'qsv', 'vaapi', 'rkmpp'];
  static const _rextTypes = ['nvenc', 'qsv', 'vaapi'];
  static const _hwaTypes = ['amf', 'nvenc', 'qsv', 'vaapi', 'rkmpp', 'videotoolbox'];

  // Values are the server's lowercase/PascalCase enum names, sent as is.
  static const _tonemapAlgorithms = [
    ('none', 'None'),
    ('clip', 'Clip'),
    ('linear', 'Linear'),
    ('gamma', 'Gamma'),
    ('reinhard', 'Reinhard'),
    ('hable', 'Hable'),
    ('mobius', 'Mobius'),
    ('bt2390', 'BT.2390'),
  ];
  static const _tonemapModes = [
    ('auto', 'Auto'),
    ('max', 'Max'),
    ('rgb', 'RGB'),
    ('lum', 'Luminance'),
    ('itp', 'ITP'),
  ];
  static const _tonemapRanges = [
    ('auto', 'Auto'),
    ('tv', 'TV'),
    ('pc', 'PC'),
  ];
  static const _encoderPresets = [
    'veryslow',
    'slower',
    'slow',
    'medium',
    'fast',
    'faster',
    'veryfast',
    'superfast',
    'ultrafast',
  ];
  static const _deinterlaceMethods = [
    ('yadif', 'YADIF'),
    ('bwdif', 'BWDIF'),
  ];
  static const _downmixAlgorithms = [
    ('None', 'None'),
    ('Dave750', 'Dave750'),
    ('NightmodeDialogue', 'Nightmode Dialogue'),
    ('Rfc7845', 'RFC 7845'),
    ('Ac4', 'AC-4'),
  ];

  @override
  void initState() {
    super.initState();
    _api = GetIt.instance<MediaServerClient>().adminSystemApi;
    _load();
  }

  Future<Map<String, dynamic>> _fetch() => _api.getNamedConfiguration('encoding');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _fetch();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
      });
      hostDraft(
        AdminDraft.single(
          working: config,
          reload: _fetch,
          post: (value) => _api.updateNamedConfiguration('encoding', value),
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
    final l10n = AppLocalizations.of(context);
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _config == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminPlaybackLoadFailed,
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

    // A missing type counts as none.
    final type = _config!['HardwareAccelerationType']?.toString() ?? '';
    final accel = type.isEmpty ? 'none' : type;
    final isHwa = _hwaTypes.contains(accel);
    final qsvOrVaapi = accel == 'qsv' || accel == 'vaapi';
    final codecs = _hwDecodeCodecs.where((c) => c.$3.contains(accel)).toList();

    final toneMapping = [
      if (qsvOrVaapi) ...[
        _switch('EnableVppTonemapping', l10n.adminPlaybackEnableVppTonemapping),
        _number('VppTonemappingBrightness',
            l10n.adminPlaybackVppTonemappingBrightness,
            fallback: 16, max: 100, decimal: true),
        _number('VppTonemappingContrast',
            l10n.adminPlaybackVppTonemappingContrast,
            fallback: 1, min: 1, max: 2, decimal: true),
      ],
      if (accel == 'videotoolbox')
        _switch('EnableVideoToolboxTonemapping',
            l10n.adminPlaybackEnableVtTonemapping),
      if (accel == 'none' || isHwa) ...[
        if (isHwa)
          _switch('EnableTonemapping', l10n.adminPlaybackEnableTonemapping),
        _dropdown('TonemappingAlgorithm',
            l10n.adminPlaybackTonemappingAlgorithm, _tonemapAlgorithms),
        if (isHwa)
          _dropdown('TonemappingMode', l10n.adminPlaybackTonemappingMode,
              _tonemapModes),
        _dropdown('TonemappingRange', l10n.adminPlaybackTonemappingRange,
            _tonemapRanges),
        _number('TonemappingDesat', l10n.adminPlaybackTonemappingDesat,
            fallback: 0, decimal: true),
        _number('TonemappingPeak', l10n.adminPlaybackTonemappingPeak,
            fallback: 100, decimal: true),
        _number('TonemappingParam', l10n.adminPlaybackTonemappingParam,
            fallback: 0, decimal: true),
      ],
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
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
                  _dropdown(
                    'HardwareAccelerationType',
                    l10n.adminPlaybackHwAccelLabel,
                    [
                      for (final o in _hwAccelOptions)
                        (o.$1, o.$1 == 'none' ? l10n.none : o.$2),
                    ],
                  ),
                  if (accel != 'none')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        l10n.adminPlaybackHwAccelWarning,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  if (accel == 'vaapi')
                    _text('VaapiDevice', l10n.adminPlaybackVaapiDevice,
                        hint: '/dev/dri/renderD128'),
                  if (accel == 'qsv')
                    _text('QsvDevice', l10n.adminPlaybackQsvDevice),
                  if (accel != 'none' && codecs.isNotEmpty)
                    _codecChips(l10n, codecs),
                  if (_tenBitTypes.contains(accel)) ...[
                    _switch('EnableDecodingColorDepth10Hevc',
                        l10n.adminPlaybackColorDepth10Hevc),
                    _switch('EnableDecodingColorDepth10Vp9',
                        l10n.adminPlaybackColorDepth10Vp9),
                  ],
                  if (_rextTypes.contains(accel)) ...[
                    _switch('EnableDecodingColorDepth10HevcRext',
                        l10n.adminPlaybackColorDepth10HevcRext),
                    _switch('EnableDecodingColorDepth12HevcRext',
                        l10n.adminPlaybackColorDepth12HevcRext),
                  ],
                  if (accel == 'nvenc')
                    _switch('EnableEnhancedNvdecDecoder',
                        l10n.adminPlaybackEnhancedNvdec),
                  if (accel == 'qsv')
                    _switch('PreferSystemNativeHwDecoder',
                        l10n.adminPlaybackPreferNativeDecoder),
                ],
              ),
              if (accel != 'none')
                adminSection(
                  context,
                  title: l10n.adminPlaybackHwEncodingSection,
                  icon: Icons.developer_board,
                  children: [
                    _switch('EnableHardwareEncoding',
                        l10n.adminPlaybackEnableHwEncoding),
                    if (qsvOrVaapi) ...[
                      _switch('EnableIntelLowPowerH264HwEncoder',
                          l10n.adminPlaybackIntelLowPowerH264),
                      _switch('EnableIntelLowPowerHevcHwEncoder',
                          l10n.adminPlaybackIntelLowPowerHevc),
                    ],
                  ],
                ),
              adminSection(
                context,
                title: l10n.adminPlaybackEncoding,
                icon: Icons.movie_filter_outlined,
                children: [
                  _switch('AllowHevcEncoding', l10n.adminPlaybackAllowHevcEncoding),
                  _switch('AllowAv1Encoding', l10n.adminPlaybackAllowAv1Encoding),
                  _dropdown('EncoderPreset', l10n.adminPlaybackEncoderPreset, [
                    ('auto', l10n.adminPlaybackAutoOption),
                    for (final p in _encoderPresets) (p, p),
                  ]),
                  _number('H265Crf', l10n.adminPlaybackH265Crf,
                      fallback: 28, max: 51),
                  _number('H264Crf', l10n.adminPlaybackH264Crf,
                      fallback: 23, max: 51),
                  // -1 and 0 both let FFmpeg pick, shown as Auto and Max.
                  _dropdown(
                    'EncodingThreadCount',
                    l10n.adminPlaybackEncodingThreads,
                    [
                      (-1, l10n.adminPlaybackAutoOption),
                      for (var i = 1; i <= 16; i++) (i, '$i'),
                      (0, l10n.adminTranscodingThreadMax),
                    ],
                    helper: l10n.adminTranscodingThreadCountHelp,
                  ),
                  _dropdown('DeinterlaceMethod',
                      l10n.adminPlaybackDeinterlaceMethod, _deinterlaceMethods),
                  _switch('DeinterlaceDoubleRate',
                      l10n.adminPlaybackDeinterlaceDoubleRate),
                ],
              ),
              if (toneMapping.isNotEmpty)
                adminSection(
                  context,
                  title: l10n.adminPlaybackToneMapping,
                  icon: Icons.hdr_on_outlined,
                  children: toneMapping,
                ),
              adminSection(
                context,
                title: l10n.adminPlaybackAudioSection,
                icon: Icons.graphic_eq,
                children: [
                  _switch('EnableAudioVbr', l10n.adminPlaybackEnableAudioVbr),
                  _number('DownMixAudioBoost', l10n.adminPlaybackDownmixBoost,
                      fallback: 2, min: 0.5, max: 3, decimal: true),
                  _dropdown('DownMixStereoAlgorithm',
                      l10n.adminPlaybackDownmixAlgorithm, _downmixAlgorithms),
                  _dropdown(
                    'HlsAudioSeekStrategy',
                    l10n.adminTranscodingAudioSeek,
                    [
                      ('TrimCopiedAudio', l10n.adminTranscodingTrimCopiedAudio),
                      ('TranscodeAudio', l10n.adminTranscodingTranscodeAudio),
                    ],
                    helper: l10n.adminTranscodingAudioSeekHelp,
                  ),
                  _number('MaxMuxingQueueSize', l10n.adminPlaybackMaxMuxingQueue,
                      fallback: 2048),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminGeneralSectionPaths,
                icon: Icons.folder_outlined,
                children: [
                  _keyed(
                    'EncoderAppPathDisplay',
                    adminFieldRow(
                      label: l10n.adminTranscodingFfmpegPath,
                      helper: l10n.adminTranscodingFfmpegPathHelp,
                      anchor: 'transcoding.EncoderAppPathDisplay',
                      child: TextFormField(
                        initialValue:
                            _config!['EncoderAppPathDisplay']?.toString() ?? '',
                        enabled: false,
                        decoration: adminInputDecoration(),
                      ),
                    ),
                  ),
                  _pathField('TranscodingTempPath',
                      l10n.adminPlaybackTranscodeTempPath,
                      writable: true),
                  _pathField(
                      'FallbackFontPath', l10n.adminPlaybackFallbackFontPath),
                  _switch('EnableFallbackFont', l10n.adminPlaybackFallbackFont),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminPlaybackStreaming,
                icon: Icons.stream,
                children: [
                  _switch('EnableSubtitleExtraction',
                      l10n.adminPlaybackEnableSubtitleExtraction),
                  _switch('EnableThrottling', l10n.adminPlaybackThrottleBuffering),
                  _switch('EnableSegmentDeletion',
                      l10n.adminPlaybackSegmentDeletion),
                  _number('ThrottleDelaySeconds', l10n.adminPlaybackThrottleDelay,
                      fallback: 180, min: 10, max: 3600),
                  _number('SegmentKeepSeconds', l10n.adminPlaybackSegmentKeep,
                      fallback: 720, min: 10, max: 3600),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Rows come and go with the hardware type, so each is keyed by its config
  /// key. Otherwise a text field's state moves to the row that takes its slot.
  Widget _keyed(String key, Widget row) =>
      KeyedSubtree(key: ValueKey(key), child: row);

  Widget _codecChips(
    AppLocalizations l10n,
    List<(String, String, List<String>)> codecs,
  ) {
    final raw = _config!['HardwareDecodingCodecs'];
    final enabled = raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
    return _keyed(
      'HardwareDecodingCodecs',
      adminFieldRow(
        label: l10n.adminTranscodingDecodingFor,
        anchor: 'transcoding.HardwareDecodingCodecs',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in codecs)
              FilterChip(
                label: Text(c.$2),
                selected: enabled.contains(c.$1),
                onSelected: (on) => _set(
                  'HardwareDecodingCodecs',
                  on
                      ? [...enabled, c.$1]
                      : enabled.where((e) => e != c.$1).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _text(String key, String label, {String? hint}) {
    return _keyed(
      key,
      adminFieldRow(
        label: label,
        anchor: 'transcoding.$key',
        child: TextFormField(
          initialValue: _config![key]?.toString() ?? '',
          decoration: adminInputDecoration(hint: hint),
          onChanged: (v) {
            _config![key] = v;
            edited();
          },
        ),
      ),
    );
  }

  Widget _number(
    String key,
    String label, {
    required num fallback,
    num min = 0,
    num? max,
    bool decimal = false,
  }) {
    return _keyed(
      key,
      adminFieldRow(
        label: label,
        anchor: 'transcoding.$key',
        child: adminNumberInput(
          text: _config![key]?.toString() ?? '',
          fallback: fallback,
          min: min,
          max: max,
          decimal: decimal,
          onChanged: (n) {
            _config![key] = n;
            edited();
          },
        ),
      ),
    );
  }

  Widget _switch(String key, String title) {
    return _keyed(
      key,
      adminSwitchRow(
        title: title,
        anchor: 'transcoding.$key',
        value: _config![key] as bool? ?? false,
        onChanged: (v) => _set(key, v),
      ),
    );
  }

  Widget _dropdown<T>(
    String key,
    String label,
    List<(T, String)> options, {
    String? helper,
  }) {
    final current = _config![key];
    final known = options.any((o) => o.$1 == current);
    return _keyed(
      key,
      adminFieldRow(
        label: label,
        helper: helper,
        anchor: 'transcoding.$key',
        child: DropdownButtonFormField<T>(
          initialValue: current is T ? current : null,
          isExpanded: true,
          decoration: adminInputDecoration(),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o.$1, child: Text(o.$2)),
            // A value this list doesn't know stays as is, so saving keeps it.
            if (current is T && !known)
              DropdownMenuItem(value: current, child: Text('$current')),
          ],
          onChanged: (v) => _set(key, v),
        ),
      ),
    );
  }

  Widget _pathField(String key, String label, {bool writable = false}) {
    final l10n = AppLocalizations.of(context);
    final isBrowsing = _browsingField == key;
    return _keyed(
      key,
      adminFieldRow(
        label: label,
        anchor: 'transcoding.$key',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey(_picks),
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
                  validateWritable: writable,
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
      ),
    );
  }
}
