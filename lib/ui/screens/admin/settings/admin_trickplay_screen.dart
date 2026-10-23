import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_slider.dart';
import '../admin_draft.dart';
import '../widgets/admin_form_styles.dart';
import 'admin_number_input.dart';

class AdminTrickplayScreen extends StatefulWidget {
  const AdminTrickplayScreen({super.key});

  @override
  State<AdminTrickplayScreen> createState() => _AdminTrickplayScreenState();
}

class _AdminTrickplayScreenState extends State<AdminTrickplayScreen>
    with AdminDraftHost {
  late final AdminSystemApi _api;
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;

  List<(String, String)> _scanBehaviors(AppLocalizations l10n) => [
    ('NonBlocking', l10n.adminTrickplayNonBlocking),
    ('Blocking', l10n.adminTrickplayBlocking),
  ];

  List<(String, String)> _priorities(AppLocalizations l10n) => [
    ('High', l10n.adminTrickplayPriorityHigh),
    ('AboveNormal', l10n.adminTrickplayPriorityAboveNormal),
    ('Normal', l10n.adminTrickplayPriorityNormal),
    ('BelowNormal', l10n.adminTrickplayPriorityBelowNormal),
    ('Idle', l10n.adminTrickplayPriorityIdle),
  ];

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
      config['TrickplayOptions'] ??= <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _config = config;
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

  /// Edited in place. The draft then sees TrickplayOptions changed and lays
  /// the whole object over the fresh config at save.
  Map<String, dynamic> get _opts =>
      _config!['TrickplayOptions'] as Map<String, dynamic>;

  void _set(String key, Object? value) {
    setState(() => _opts[key] = value);
    edited();
  }

  int _intOpt(String key, int fallback) =>
      (_opts[key] as num?)?.toInt() ?? fallback;

  bool _boolOpt(String key) => _opts[key] as bool? ?? false;

  String _widthResolutionsText() {
    final raw = _opts['WidthResolutions'];
    if (raw is List) return raw.map((e) => e.toString()).join(', ');
    return '320';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _config == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminTrickplayLoadFailed,
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

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminDrawerTrickplay,
          subtitle: l10n.adminTrickplayDescription,
          icon: Icons.view_comfy,
        ),
        draftKeyed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adminSection(
                context,
                title: l10n.general,
                icon: Icons.tune,
                children: [
                  _switch('EnableHwAcceleration', l10n.adminTrickplayHwAccel),
                  _switch('EnableHwEncoding', l10n.adminTrickplayHwEncoding),
                  _switch(
                    'EnableKeyFrameOnlyExtraction',
                    l10n.adminTrickplayKeyFrameOnly,
                    subtitle: l10n.adminTrickplayKeyFrameOnlySubtitle,
                  ),
                  _dropdown('ScanBehavior', l10n.adminTrickplayScanBehavior,
                      _scanBehaviors(l10n), 'NonBlocking'),
                  _dropdown('ProcessPriority',
                      l10n.adminTrickplayProcessPriority, _priorities(l10n),
                      'BelowNormal'),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminTrickplayImageSettings,
                icon: Icons.image_outlined,
                children: [
                  _number('Interval', l10n.adminTrickplayInterval,
                      fallback: 10000,
                      min: 1,
                      helper: l10n.adminTrickplayIntervalSubtitle),
                  adminFieldRow(
                    label: l10n.adminTrickplayWidthResolutions,
                    helper: l10n.adminTrickplayWidthResolutionsHint,
                    anchor: 'trickplay.WidthResolutions',
                    child: TextFormField(
                      initialValue: _widthResolutionsText(),
                      decoration: adminInputDecoration(),
                      onChanged: (v) {
                        _opts['WidthResolutions'] = v
                            .split(',')
                            .map((s) => int.tryParse(s.trim()))
                            .where((n) => n != null && n > 0)
                            .toList();
                        edited();
                      },
                    ),
                  ),
                  _number('TileWidth', l10n.adminTrickplayTileWidth,
                      fallback: 10, min: 1),
                  _number('TileHeight', l10n.adminTrickplayTileHeight,
                      fallback: 10, min: 1),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminTrickplayQuality,
                icon: Icons.high_quality_outlined,
                children: [
                  _slider('Qscale', l10n.adminTrickplayQScale,
                      min: 2, max: 31, fallback: 4,
                      helper: l10n.adminTrickplayQScaleSubtitle),
                  _slider('JpegQuality', l10n.adminTrickplayJpegQuality,
                      min: 1, max: 100, fallback: 90),
                ],
              ),
              adminSection(
                context,
                title: l10n.adminTrickplayProcessing,
                icon: Icons.memory,
                children: [
                  _number('ProcessThreads', l10n.adminTrickplayProcessThreads,
                      fallback: 1, helper: l10n.adminPlaybackAutomatic),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switch(String key, String title, {String? subtitle}) {
    return adminSwitchRow(
      title: title,
      subtitle: subtitle,
      anchor: 'trickplay.$key',
      value: _boolOpt(key),
      onChanged: (v) => _set(key, v),
    );
  }

  Widget _dropdown(
    String key,
    String label,
    List<(String, String)> options,
    String fallback,
  ) {
    final current = _opts[key]?.toString() ?? fallback;
    return adminFieldRow(
      label: label,
      anchor: 'trickplay.$key',
      child: DropdownButtonFormField<String>(
        initialValue:
            options.any((o) => o.$1 == current) ? current : fallback,
        isExpanded: true,
        decoration: adminInputDecoration(),
        items: options
            .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
            .toList(),
        onChanged: (v) => _set(key, v),
      ),
    );
  }

  /// Empty text writes [fallback], the default.
  Widget _number(
    String key,
    String label, {
    required int fallback,
    int min = 0,
    String? helper,
  }) {
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'trickplay.$key',
      child: adminNumberInput(
        text: _intOpt(key, fallback).toString(),
        fallback: fallback,
        min: min,
        onChanged: (n) {
          _opts[key] = n;
          edited();
        },
      ),
    );
  }

  Widget _slider(
    String key,
    String label, {
    required int min,
    required int max,
    required int fallback,
    String? helper,
  }) {
    final value = _intOpt(key, fallback).clamp(min, max);
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'trickplay.$key',
      child: Row(
        children: [
          Expanded(
            child: adaptiveSlider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value',
              onChanged: (v) => _set(key, v.round()),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
