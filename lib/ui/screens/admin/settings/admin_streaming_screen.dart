import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../admin_draft.dart';
import '../admin_nav.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/premiere_note.dart';
import 'admin_number_input.dart';

class AdminStreamingScreen extends StatefulWidget {
  const AdminStreamingScreen({super.key});

  @override
  State<AdminStreamingScreen> createState() => _AdminStreamingScreenState();
}

class _AdminStreamingScreenState extends State<AdminStreamingScreen>
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

  /// The limit in Mbps, unrounded, empty for none.
  String _mbpsText() {
    final bps = (_config!['RemoteClientBitrateLimit'] as num?) ?? 0;
    if (bps == 0) return '';
    final mbps = bps / 1000000;
    return mbps == mbps.truncateToDouble()
        ? mbps.toInt().toString()
        : mbps.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _config == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminStreamingLoadFailed,
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
          title: l10n.adminDrawerStreaming,
          subtitle: l10n.adminStreamingDescription,
          icon: Icons.stream,
        ),
        draftKeyed(
          adminSection(
            context,
            title: l10n.general,
            icon: Icons.speed,
            children: [
              adminFieldRow(
                label: l10n.adminStreamingBitrateLimit,
                helper: l10n.adminStreamingBitrateLimitHint,
                anchor: 'streaming.RemoteClientBitrateLimit',
                // The server stores bits per second in an int, so the limit
                // tops out at 2147.25 Mbps. Empty means no limit.
                child: adminNumberInput(
                  text: _mbpsText(),
                  fallback: 0,
                  max: 2147.25,
                  decimal: true,
                  suffixText: 'Mbps',
                  onChanged: (mbps) {
                    _config!['RemoteClientBitrateLimit'] =
                        (mbps * 1000000).truncate();
                    edited();
                  },
                ),
              ),
              if (AdminServerScope.isEmby(context))
                adminFieldRow(
                  label: l10n.adminStreamingStreamLimit,
                  helper: l10n.adminStreamingStreamLimitHelp,
                  anchor: 'streaming.SimultaneousStreamLimit',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      adminNumberInput(
                        text: '${_config!['SimultaneousStreamLimit'] ?? 0}',
                        fallback: 0,
                        onChanged: (n) {
                          _config!['SimultaneousStreamLimit'] = n;
                          edited();
                        },
                      ),
                      const PremiereNote(margin: EdgeInsets.only(top: 8)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
