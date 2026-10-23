import 'package:moonfin_design/moonfin_design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../providers/admin_user_providers.dart';
import 'admin_form_styles.dart';
import 'session_detail_sheet.dart';

/// The play method to show for [session]: 'Remux', 'DirectStream',
/// 'Transcode', 'DirectPlay', or null when nothing plays.
String? displayPlayMethod(Map<String, dynamic> session) {
  if (session['NowPlayingItem'] == null) return null;
  final transcoding = session['TranscodingInfo'] as Map<String, dynamic>?;
  final videoDirect = transcoding?['IsVideoDirect'] == true;
  if ((videoDirect || transcoding?['VideoCodec'] == null) &&
      transcoding?['IsAudioDirect'] == true) {
    return 'Remux';
  }
  if (videoDirect) return 'DirectStream';
  return switch ((session['PlayState'] as Map?)?['PlayMethod']) {
    'Transcode' => 'Transcode',
    // A DirectStream play method shows as direct play too.
    'DirectStream' || 'DirectPlay' => 'DirectPlay',
    _ => null,
  };
}

String playMethodLabel(String? method, AppLocalizations l10n) =>
    switch (method) {
      'Remux' => l10n.adminPlayMethodRemux,
      'DirectStream' => l10n.adminPlayMethodDirectStream,
      'Transcode' => l10n.transcoding,
      _ => l10n.adminPlayMethodDirectPlay,
    };

class ActiveSessionsCard extends ConsumerStatefulWidget {
  const ActiveSessionsCard({super.key});

  @override
  ConsumerState<ActiveSessionsCard> createState() => _ActiveSessionsCardState();
}

class _ActiveSessionsCardState extends ConsumerState<ActiveSessionsCard> {
  void _openDetail(Map<String, dynamic> session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SessionDetailSheet(session: session),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Kept current by the server's Sessions feed, so nothing polls here.
    final sessionsAsync = ref.watch(adminSessionsProvider);
    final sessions = sessionsAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    final loading = sessionsAsync.isLoading && !sessionsAsync.hasValue;
    final failed = sessionsAsync.hasError && !sessionsAsync.hasValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: adminSectionLabel(context, l10n.adminActiveSessions,
                  icon: Icons.people),
            ),
            if (loading)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Text('${sessions.length}', style: theme.textTheme.titleLarge),
            const SizedBox(width: AppSpacing.spaceXs),
          ],
        ),
        adminGlassGroup(
          context,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.spaceLg,
                vertical: AppSpacing.spaceMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Text(l10n.adminSessionsLoadFailed, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => ref.invalidate(adminSessionsProvider),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              )
            else if (!loading && sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(l10n.adminNoActiveSessions)),
              )
            else
              ...sessions.map((session) {
                final userName =
                    session['UserName'] as String? ?? l10n.unknown;
                final client = session['Client'] as String? ?? '';
                final device = session['DeviceName'] as String? ?? '';
                final nowPlaying =
                    session['NowPlayingItem'] as Map<String, dynamic>?;
                final playState =
                    session['PlayState'] as Map<String, dynamic>?;
                final isPaused = playState?['IsPaused'] as bool? ?? false;
                final runTimeTicks =
                    (nowPlaying?['RunTimeTicks'] as num?)?.toDouble() ?? 0;
                final positionTicks =
                    (playState?['PositionTicks'] as num?)?.toDouble() ?? 0;
                final progress = (nowPlaying != null && runTimeTicks > 0)
                    ? (positionTicks / runTimeTicks).clamp(0.0, 1.0)
                    : null;

                return InkWell(
                  onTap: () => _openDetail(session),
                  borderRadius: AppRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : '?',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color:
                                      theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          userName,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _platformIcon(client, theme),
                                    ],
                                  ),
                                  Text(
                                    nowPlaying != null
                                        ? (nowPlaying['Name'] as String? ??
                                        l10n.unknown)
                                        : '$client · $device',
                                    style: theme.textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _playMethodBadge(session, isPaused, theme),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right,
                                size: 16,
                                color: theme.colorScheme.outline),
                          ],
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 42),
                            child: ClipRRect(
                              borderRadius: AppRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _platformIcon(String client, ThemeData theme) {
    final lc = client.toLowerCase();
    final IconData icon;
    if (lc.contains('android tv') ||
        lc.contains('fire tv') ||
        lc.contains('apple tv') ||
        lc.contains('roku')) {
      icon = Icons.tv;
    } else if (lc.contains('android')) {
      icon = Icons.android;
    } else if (lc.contains('ios') ||
        lc.contains('iphone') ||
        lc.contains('ipad') ||
        lc.contains('apple')) {
      icon = Icons.phone_iphone;
    } else if (lc.contains('web') || lc.contains('browser')) {
      icon = Icons.language;
    } else {
      icon = Icons.devices_other;
    }
    return Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant);
  }

  Widget _playMethodBadge(
    Map<String, dynamic> session,
    bool isPaused,
    ThemeData theme,
  ) {
    final l10n = AppLocalizations.of(context);
    final method = displayPlayMethod(session);
    final IconData icon;
    final String label;
    final Color bg;
    final Color fg;
    if (session['NowPlayingItem'] == null) {
      icon = Icons.stop_circle_outlined;
      label = l10n.idle;
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else if (isPaused) {
      icon = Icons.pause;
      label = l10n.paused;
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else if (method == 'Transcode') {
      final bitrate = (session['TranscodingInfo'] as Map?)?['Bitrate'] as int?;
      final mbps = bitrate != null
          ? ' ${(bitrate / 1000000).toStringAsFixed(1)}M'
          : '';
      icon = Icons.swap_horiz;
      label = '${l10n.transcoding}$mbps';
      bg = theme.colorScheme.secondaryContainer;
      fg = theme.colorScheme.onSecondaryContainer;
    } else {
      icon = method == 'DirectPlay' ? Icons.play_arrow : Icons.sync_alt;
      label = playMethodLabel(method, l10n);
      bg = theme.colorScheme.primaryContainer;
      fg = theme.colorScheme.onPrimaryContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: AppRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

