import 'package:moonfin_design/moonfin_design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../util/play_method_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/admin_user_providers.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../../../widgets/adaptive/adaptive_slider.dart';
import 'active_sessions_card.dart';
import 'admin_form_styles.dart';

class SessionDetailSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;

  const SessionDetailSheet({super.key, required this.session});

  @override
  ConsumerState<SessionDetailSheet> createState() => _SessionDetailSheetState();
}

class _SessionDetailSheetState extends ConsumerState<SessionDetailSheet> {
  late final SessionApi _sessionApi;
  late Map<String, dynamic> _session;
  bool _busy = false;
  double? _seekPosition;

  @override
  void initState() {
    super.initState();
    _sessionApi = GetIt.instance<MediaServerClient>().sessionApi;
    _session = widget.session;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.adminCommandFailed(describeError(e, l10n))),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPlayState(String command, {int? seekTicks}) {
    return _run(
      () => _sessionApi.sendPlayStateCommand(
        _session['Id']?.toString() ?? '',
        command,
        seekPositionTicks: seekTicks,
      ),
    );
  }

  Future<void> _sendGeneral(String commandName, {Map<String, String>? args}) {
    return _run(
      () => _sessionApi.sendGeneralCommand(
        _session['Id']?.toString() ?? '',
        commandName,
        arguments: args,
      ),
    );
  }

  void _showSendMessageDialog() {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.adminSendMessage),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: l10n.adminMessageTextHint),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                _run(
                  () => _sessionApi.sendMessage(
                    _session['Id']?.toString() ?? '',
                    text,
                    timeoutMs: 5000,
                  ),
                );
              }
            },
            child: Text(l10n.send),
          ),
        ],
      ),
    );
  }

  void _showVolumeDialog() {
    final volumeData = _session['PlayState']?['VolumeLevel'] as num?;
    var volume = volumeData?.toDouble() ?? 50.0;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog.adaptive(
          title: Text(l10n.adminSetVolume),
          content: adaptiveSlider(
            value: volume,
            min: 0,
            max: 100,
            divisions: 100,
            label: '${volume.round()}%',
            onChanged: (v) => setInner(() => volume = v),
          ),
          actions: [
            adaptiveDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _sendGeneral(
                  'SetVolume',
                  args: {'Volume': volume.round().toString()},
                );
              },
              child: Text(l10n.set),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The Sessions feed keeps this entry current while the sheet is open.
    for (final s in ref.watch(adminSessionsProvider).valueOrNull ?? const []) {
      if (s['Id'] == widget.session['Id']) _session = s;
    }
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final sessionId = _session['Id']?.toString() ?? '';
    if (sessionId.isEmpty) {
      return const SizedBox.shrink();
    }
    final userName = _session['UserName'] as String? ?? l10n.unknown;
    final client = _session['Client'] as String? ?? '';
    final device = _session['DeviceName'] as String? ?? '';
    final appVersion = _session['ApplicationVersion'] as String? ?? '';
    final nowPlaying = _session['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = _session['PlayState'] as Map<String, dynamic>?;
    final transcodingInfo =
        _session['TranscodingInfo'] as Map<String, dynamic>?;

    // Only sessions that take remote commands get the controls.
    final canControl = _session['ServerId'] != null &&
        _session['SupportsRemoteControl'] == true;
    final isPaused = playState?['IsPaused'] as bool? ?? false;
    final isMuted = playState?['IsMuted'] as bool? ?? false;
    final positionTicks = (playState?['PositionTicks'] as num?)?.toInt();
    final runtimeTicks = (nowPlaying?['RunTimeTicks'] as num?)?.toInt();

    String ticksToTime(int ticks) {
      final duration = Duration(microseconds: ticks ~/ 10);
      final h = duration.inHours;
      final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$s' : '$m:$s';
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: AppRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$client · $device${appVersion.isNotEmpty ? ' ($appVersion)' : ''}',
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_busy)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (nowPlaying != null) ...[
                    adminSection(
                      context,
                      title: l10n.nowPlaying,
                      icon: Icons.play_circle_outline,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nowPlaying['Name'] as String? ?? '',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if ((nowPlaying['SeriesName'] as String?) != null)
                                Text(
                                  nowPlaying['SeriesName'] as String,
                                  style: theme.textTheme.bodySmall,
                                ),
                              if (positionTicks != null &&
                                  runtimeTicks != null &&
                                  runtimeTicks > 0) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      ticksToTime(positionTicks),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                    Expanded(
                                      child: canControl
                                          ? adaptiveSlider(
                                              value:
                                                  (_seekPosition ??
                                                          positionTicks / runtimeTicks)
                                                      .clamp(0.0, 1.0),
                                              onChanged: (v) =>
                                                  setState(() => _seekPosition = v),
                                              onChangeEnd: (v) {
                                                final target = (v * runtimeTicks).round();
                                                _seekPosition = null;
                                                _sendPlayState('Seek', seekTicks: target);
                                              },
                                            )
                                          : Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                              child: LinearProgressIndicator(
                                                value: (positionTicks /
                                                        runtimeTicks)
                                                    .clamp(0.0, 1.0),
                                              ),
                                            ),
                                    ),
                                    Text(
                                      ticksToTime(runtimeTicks),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ],
                              if (isPaused)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer,
                                    borderRadius: AppRadius.circular(6),
                                  ),
                                  child: Text(
                                    l10n.paused,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (nowPlaying != null && canControl) ...[
                    adminSectionLabel(context, l10n.playback,
                        icon: Icons.tune),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlButton(
                          icon: Icons.skip_previous,
                          label: l10n.sessionPrev,
                          onTap: () => _sendPlayState('PreviousTrack'),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: Icons.replay_10,
                          label: l10n.sessionRewind,
                          onTap: () => _sendPlayState('Rewind'),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: isPaused ? Icons.play_arrow : Icons.pause,
                          label: isPaused ? l10n.play : l10n.pause,
                          onTap: () => _sendPlayState('PlayPause'),
                          primary: true,
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: Icons.forward_10,
                          label: l10n.sessionForward,
                          onTap: () => _sendPlayState('FastForward'),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: Icons.skip_next,
                          label: l10n.sessionNext,
                          onTap: () => _sendPlayState('NextTrack'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: _ControlButton(
                        icon: Icons.stop,
                        label: l10n.stop,
                        onTap: () => _sendPlayState('Stop'),
                        color: theme.colorScheme.error,
                      ),
                    ),
                    adminSectionLabel(context, l10n.volume,
                        icon: Icons.volume_up_outlined),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlButton(
                          icon: isMuted ? Icons.volume_off : Icons.volume_up,
                          label: isMuted ? l10n.unmute : l10n.mute,
                          onTap: () =>
                              _sendGeneral(isMuted ? 'Unmute' : 'Mute'),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: Icons.volume_down,
                          label: l10n.sessionVolumeDown,
                          onTap: () => _sendGeneral('VolumeDown'),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: Icons.volume_up,
                          label: l10n.sessionVolumeUp,
                          onTap: () => _sendGeneral('VolumeUp'),
                        ),
                        const SizedBox(width: 8),
                        _ControlButton(
                          icon: Icons.tune,
                          label: l10n.set,
                          onTap: _showVolumeDialog,
                        ),
                      ],
                    ),
                  ],

                  if (nowPlaying != null && transcodingInfo != null) ...[
                    adminSectionLabel(
                      context,
                      playMethodLabel(displayPlayMethod(_session), l10n),
                      icon: Icons.swap_horiz,
                    ),
                    _InfoGrid({
                      l10n.videoCodec:
                          transcodingInfo['VideoCodec'] as String? ?? '–',
                      l10n.audioCodec:
                          transcodingInfo['AudioCodec'] as String? ?? '–',
                      l10n.container:
                          transcodingInfo['Container'] as String? ?? '–',
                      l10n.bitrate: transcodingInfo['Bitrate'] != null
                          ? '${((transcodingInfo['Bitrate'] as int) / 1000000).toStringAsFixed(1)} Mbps'
                          : '–',
                      l10n.hwAccel:
                          transcodingInfo['HardwareAccelerationType']
                              as String? ?? '–',
                      l10n.completion:
                          transcodingInfo['CompletionPercentage'] != null
                          ? '${(transcodingInfo['CompletionPercentage'] as num).toStringAsFixed(1)}%'
                          : '–',
                      l10n.transcodeReasons:
                          (transcodingInfo['TranscodeReasons'] as List?)
                                  ?.map((r) => transcodeReasonLabel('$r', l10n))
                                  .join(', ') ??
                              '–',
                    }),
                  ],

                  if (canControl) ...[
                    adminSectionLabel(context, l10n.actions,
                        icon: Icons.bolt_outlined),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.message_outlined),
                            label: Text(l10n.adminSendMessage),
                            onPressed: _showSendMessageDialog,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          // GoHome only asks the client to show its home
                          // screen, it signs nothing out.
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.home_outlined),
                            label: Text(l10n.adminSessionGoHome),
                            onPressed: () => _run(
                              () => _sessionApi.sendGeneralCommand(
                                sessionId,
                                'GoHome',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final Color? color;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        color ??
        (primary ? theme.colorScheme.primary : theme.colorScheme.onSurface);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: primary ? 36 : 28, color: fg),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Map<String, String> data;
  const _InfoGrid(this.data);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data.entries.toList();
    return adminListCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: entries
              .map(
                (e) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.key,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    Text(
                      e.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
