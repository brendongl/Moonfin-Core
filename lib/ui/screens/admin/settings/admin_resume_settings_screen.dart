import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_slider.dart';
import '../admin_draft.dart';
import '../widgets/admin_form_styles.dart';
import 'admin_number_input.dart';

class AdminResumeSettingsScreen extends StatefulWidget {
  const AdminResumeSettingsScreen({super.key});

  @override
  State<AdminResumeSettingsScreen> createState() =>
      _AdminResumeSettingsScreenState();
}

class _AdminResumeSettingsScreenState extends State<AdminResumeSettingsScreen>
    with AdminDraftHost {
  late final AdminSystemApi _api;
  Map<String, dynamic>? _config;
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

  void _set(String key, Object? value) {
    setState(() => _config![key] = value);
    edited();
  }

  int _intVal(String key, [int fallback = 0]) =>
      (_config![key] as num?)?.toInt() ?? fallback;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _config == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminResumeLoadFailed,
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
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminDrawerResume,
          subtitle: l10n.adminResumeDescription,
          icon: Icons.play_circle_outline,
        ),
        draftKeyed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              adminSection(
                context,
                title: l10n.adminResumeVideo,
                icon: Icons.movie_outlined,
                children: [
                  _percentSlider(
                    'MinResumePct',
                    l10n.adminMinResumePercentage,
                    min: 0,
                    helper: l10n.adminMinResumeSubtitle,
                  ),
                  _percentSlider(
                    'MaxResumePct',
                    l10n.adminMaxResumePercentage,
                    min: 1,
                    helper: l10n.adminMaxResumeSubtitle,
                  ),
                  _number(
                    'MinResumeDurationSeconds',
                    l10n.adminMinResumeDuration,
                    helper: l10n.adminMinResumeDurationSubtitle,
                    fallback: 300,
                  ),
                ],
              ),
              // Both audiobook values are minutes, not percentages.
              adminSection(
                context,
                title: l10n.adminResumeAudiobooks,
                icon: Icons.headphones_outlined,
                children: [
                  _number(
                    'MinAudiobookResume',
                    l10n.adminResumeMinAudiobookMinutes,
                    helper: l10n.adminResumeMinAudiobookHelp,
                    fallback: 5,
                    max: 100,
                  ),
                  _number(
                    'MaxAudiobookResume',
                    l10n.adminResumeAudiobookRemaining,
                    helper: l10n.adminResumeAudiobookRemainingHelp,
                    fallback: 5,
                    min: 1,
                    max: 100,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _percentSlider(
    String key,
    String label, {
    required int min,
    String? helper,
  }) {
    final value = _intVal(key).clamp(min, 100);
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'resume.$key',
      child: Row(
        children: [
          Expanded(
            child: adaptiveSlider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: 100,
              divisions: 100 - min,
              label: '$value%',
              onChanged: (v) => _set(key, v.round()),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text('$value%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _number(
    String key,
    String label, {
    required int fallback,
    int min = 0,
    int? max,
    String? helper,
  }) {
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: 'resume.$key',
      child: adminNumberInput(
        text: _intVal(key, fallback).toString(),
        fallback: fallback,
        min: min,
        max: max,
        onChanged: (n) {
          _config![key] = n;
          edited();
        },
      ),
    );
  }
}
