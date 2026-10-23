import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../data/models/home_row.dart';
import '../../focus/glass_focus_halo.dart';
import '../../focus/locked_focus_row.dart';
import '../../horizontal_scroll_section.dart';
import '../../media_card.dart';
import '../book_glass.dart';
import '../book_see_all_button.dart';
import 'book_card.dart';

/// How a shelf renders its items.
enum BookShelfVariant {
  /// Book/audiobook covers via [BookCard] (2:3 or square by format).
  poster,

  /// Circular author avatars.
  avatar,

  /// Genre chips.
  chip,
}

/// One shelf of the Classic book library, a titled [LockedFocusRow]. The D-pad
/// gets select, long press, a remembered position (keyed by [hubKey]) and
/// edge callbacks, while touch and pointer scroll it like a plain list.
class BookShelfRow extends StatelessWidget {
  final HomeRow row;
  final String title;
  final BookShelfVariant variant;
  final String hubKey;
  final GlobalKey<LockedFocusRowState> rowKey;
  final GlobalKey? containerKey;
  final bool Function(bool isUp)? onVerticalNavigation;
  final VoidCallback? onLeftEdge;
  final void Function(AggregatedItem item) onItemTap;
  final void Function(AggregatedItem item)? onItemLongPress;
  final VoidCallback? onSeeAll;

  /// See all's D-pad stop, which Up from the shelf reaches before the shelf
  /// above.
  final FocusNode? seeAllFocusNode;

  final String? Function(AggregatedItem item) imageUrlFor;
  final String Function(AggregatedItem item)? subtitleFor;
  final bool Function(AggregatedItem item)? isAudiobookFor;
  final bool Function(AggregatedItem item)? isComicFor;
  final Duration? Function(AggregatedItem item)? remainingFor;

  /// Show the book/headphones glyph on poster cards (mixed rows).
  final bool showFormatBadges;

  final double cardWidth;

  /// Where the title and the first card start.
  final double leadingInset;

  const BookShelfRow({
    super.key,
    required this.row,
    required this.title,
    required this.variant,
    required this.hubKey,
    required this.rowKey,
    required this.onItemTap,
    required this.imageUrlFor,
    this.containerKey,
    this.onVerticalNavigation,
    this.onLeftEdge,
    this.onItemLongPress,
    this.onSeeAll,
    this.seeAllFocusNode,
    this.subtitleFor,
    this.isAudiobookFor,
    this.isComicFor,
    this.remainingFor,
    this.showFormatBadges = false,
    this.cardWidth = 132,
    this.leadingInset = 16,
  });

  static const _chipWidth = 150.0;
  static const _chipHeight = 44.0;
  static const _labelBudget = 48.0;

  bool _isAudio(AggregatedItem item) => isAudiobookFor?.call(item) ?? false;
  bool _isComic(AggregatedItem item) => isComicFor?.call(item) ?? item.isComic;

  double get _itemExtent =>
      variant == BookShelfVariant.chip ? _chipWidth : cardWidth;

  double get _rowHeight {
    switch (variant) {
      case BookShelfVariant.chip:
        return _chipHeight + 12;
      case BookShelfVariant.avatar:
        return cardWidth + _labelBudget;
      case BookShelfVariant.poster:
        final hasPosters = row.items.any((item) => !_isAudio(item));
        final imageHeight = hasPosters ? cardWidth * 1.5 : cardWidth;
        return imageHeight + _labelBudget + 12;
    }
  }

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
          trailing: onSeeAll == null
              ? null
              : BookSeeAllButton(
                  onPressed: onSeeAll!,
                  focusNode: seeAllFocusNode,
                  onNavigateUp: () => onVerticalNavigation?.call(true),
                  onNavigateDown: () =>
                      rowKey.currentState?.requestFocusFromMemory(),
                ),
          builder: (context, controller) => LockedFocusRow<AggregatedItem>(
            key: rowKey,
            items: row.items,
            hubKey: hubKey,
            controller: controller,
            height: _rowHeight,
            itemExtent: _itemExtent,
            itemSpacing: 12,
            clipBehavior: Clip.none,
            leadingPadding: 0,
            padding: EdgeInsets.fromLTRB(leadingInset, 5, 20, 5),
            onVerticalNavigation: (isUp) {
              final seeAll = seeAllFocusNode;
              if (isUp && onSeeAll != null && seeAll != null) {
                seeAll.requestFocus();
                return true;
              }
              return onVerticalNavigation?.call(isUp) ?? false;
            },
            onLeftEdge: onLeftEdge,
            onTap: (_, item) => onItemTap(item),
            onLongPress: onItemLongPress == null
                ? null
                : (_, item) => onItemLongPress!(item),
            itemBuilder: (context, item, index, isFocused) =>
                _buildItem(context, item, isFocused),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, AggregatedItem item, bool isFocused) {
    switch (variant) {
      case BookShelfVariant.chip:
        return Align(
          alignment: Alignment.topLeft,
          child: _GenreChip(
            label: item.name,
            focused: isFocused,
            onTap: () => onItemTap(item),
          ),
        );
      case BookShelfVariant.avatar:
        return Align(
          alignment: Alignment.topCenter,
          child: MediaCard(
            width: cardWidth,
            aspectRatio: 1,
            title: item.name,
            imageUrl: imageUrlFor(item),
            itemType: 'Person',
            externalIsFocused: isFocused,
            onTap: () => onItemTap(item),
            onLongPress: onItemLongPress == null
                ? null
                : () => onItemLongPress!(item),
          ),
        );
      case BookShelfVariant.poster:
        final isAudio = _isAudio(item);
        final isComic = _isComic(item);
        final remaining = isAudio ? remainingFor?.call(item) : null;
        final pct = item.playedPercentage;
        return Align(
          alignment: Alignment.topLeft,
          child: BookCard(
            item: item,
            isAudiobook: isAudio,
            isComic: isComic,
            subtitle: subtitleFor?.call(item),
            imageUrl: imageUrlFor(item),
            width: cardWidth,
            remaining: remaining,
            remainingIsTotal: pct == null || pct <= 0,
            showFormatBadge: showFormatBadges,
            externalIsFocused: isFocused,
            onTap: () => onItemTap(item),
            onLongPress: onItemLongPress == null
                ? null
                : () => onItemLongPress!(item),
          ),
        );
    }
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final bool focused;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.focused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassFocusHalo(
        focused: focused,
        scale: 1.04,
        borderRadius: BorderRadius.circular(999),
        child: bookGlassOrSolid(
          cornerRadius: 999,
          blur: 12,
          fallbackColor: AppColorScheme.onSurface.withValues(alpha: 0.08),
          context: context,
          child: SizedBox(
            width: BookShelfRow._chipWidth,
            height: BookShelfRow._chipHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
