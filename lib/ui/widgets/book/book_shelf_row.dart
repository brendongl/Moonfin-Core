import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/models/home_row.dart';
import '../../../l10n/app_localizations.dart';
import '../focus/glass_focus_halo.dart';
import '../focus/locked_focus_row.dart';
import '../horizontal_scroll_section.dart';
import '../offline_aware_image.dart';
import 'book_format_badge.dart';

/// The book library's Continue shelf, compact tiles showing each cover and how
/// far along it is. A titled [LockedFocusRow], so the D-pad gets select,
/// long-press, a remembered position (keyed by [hubKey]) and edge callbacks,
/// while touch and pointer scroll it like a plain list.
class BookShelfRow extends StatelessWidget {
  final HomeRow row;
  final String title;
  final String hubKey;
  final GlobalKey<LockedFocusRowState> rowKey;
  final GlobalKey? containerKey;
  final bool Function(bool isUp)? onVerticalNavigation;
  final VoidCallback? onLeftEdge;
  final void Function(AggregatedItem item) onItemTap;

  /// The tile's play button, which touch and pointer can reach. The D-pad
  /// select key goes to [onItemTap].
  final void Function(AggregatedItem item) onItemPlay;
  final void Function(AggregatedItem item)? onItemLongPress;

  final String? Function(AggregatedItem item) imageUrlFor;
  final String Function(AggregatedItem item)? subtitleFor;
  final bool Function(AggregatedItem item)? isAudiobookFor;
  final Duration? Function(AggregatedItem item)? remainingFor;

  final double tileWidth;

  /// Where the title and the first tile start.
  final double leadingInset;

  const BookShelfRow({
    super.key,
    required this.row,
    required this.title,
    required this.hubKey,
    required this.rowKey,
    required this.onItemTap,
    required this.onItemPlay,
    required this.imageUrlFor,
    this.containerKey,
    this.onVerticalNavigation,
    this.onLeftEdge,
    this.onItemLongPress,
    this.subtitleFor,
    this.isAudiobookFor,
    this.remainingFor,
    this.tileWidth = 300,
    this.leadingInset = 16,
  });

  static const _tileHeight = 100.0;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: containerKey,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: HorizontalScrollSection(
          title: title,
          headerPadding: EdgeInsets.only(left: leadingInset, right: 16),
          contentSpacing: 6,
          builder: (context, controller) => LockedFocusRow<AggregatedItem>(
            key: rowKey,
            items: row.items,
            hubKey: hubKey,
            controller: controller,
            height: _tileHeight + 12,
            itemExtent: tileWidth,
            itemSpacing: 12,
            clipBehavior: Clip.none,
            leadingPadding: 0,
            padding: EdgeInsets.fromLTRB(leadingInset, 5, 20, 5),
            onVerticalNavigation: onVerticalNavigation,
            onLeftEdge: onLeftEdge,
            onTap: (_, item) => onItemTap(item),
            onLongPress: onItemLongPress == null
                ? null
                : (_, item) => onItemLongPress!(item),
            itemBuilder: (context, item, index, isFocused) =>
                _buildTile(context, item, isFocused),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, AggregatedItem item, bool isFocused) {
    final isAudio = isAudiobookFor?.call(item) ?? false;
    final pct = item.playedPercentage ?? 0;
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: tileWidth,
        height: _tileHeight,
        child: _ProgressTile(
          title: item.name,
          subtitle: subtitleFor?.call(item) ?? '',
          imageUrl: imageUrlFor(item),
          isAudio: isAudio,
          progress: (pct / 100).clamp(0.0, 1.0),
          meta: bookProgressMeta(
            AppLocalizations.of(context),
            isAudiobook: isAudio,
            playedPercentage: pct,
            remaining: isAudio ? remainingFor?.call(item) : null,
          ),
          focused: isFocused,
          onTap: () => onItemTap(item),
          onPlay: () => onItemPlay(item),
          onLongPress: onItemLongPress == null
              ? null
              : () => onItemLongPress!(item),
        ),
      ),
    );
  }
}

class _ProgressTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool isAudio;
  final double progress;
  final String? meta;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onLongPress;

  const _ProgressTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.isAudio,
    required this.progress,
    required this.meta,
    required this.focused,
    required this.onTap,
    required this.onPlay,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onSurface = AppColorScheme.onSurface;
    final coverWidth = isAudio ? 72.0 : 56.0;
    final coverHeight = isAudio ? 72.0 : 84.0;
    final placeholder = ColoredBox(
      color: AppColorScheme.surfaceVariant,
      child: Icon(
        isAudio ? Icons.headphones_rounded : Icons.menu_book_rounded,
        color: onSurface.withValues(alpha: 0.4),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassFocusHalo(
        focused: focused,
        scale: 1.03,
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColorScheme.surface,
            borderRadius: AppRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadius.circular(5),
                  child: SizedBox(
                    width: coverWidth,
                    height: coverHeight,
                    child: imageUrl == null
                        ? placeholder
                        : OfflineAwareImage(
                            imageUrl: imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => placeholder,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: AppRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: onSurface.withValues(alpha: 0.14),
                          valueColor: AlwaysStoppedAnimation(
                            AppColorScheme.accent,
                          ),
                        ),
                      ),
                      if (meta != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  container: true,
                  button: true,
                  label: isAudio ? l10n.continueListening : l10n.continueReading,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onPlay,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColorScheme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: AppColorScheme.onAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
