import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../l10n/app_localizations.dart';

/// A small glyph on a card telling a book, an audiobook and a comic apart.
/// It's a solid scrim rather than glass, so rows of cards stay cheap to draw
/// on TV.
class BookFormatBadge extends StatelessWidget {
  final bool isAudiobook;
  final bool isComic;

  const BookFormatBadge({
    super.key,
    this.isAudiobook = false,
    this.isComic = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, icon) = isComic
        ? (l10n.bookFormatComic, Icons.auto_stories_rounded)
        : (isAudiobook
            ? (l10n.bookFormatAudiobook, Icons.headphones_rounded)
            : (l10n.bookFormatBook, Icons.menu_book_rounded));

    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColorScheme.scrim.withValues(alpha: 0.72),
          borderRadius: AppRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Icon(
            icon,
            size: 12,
            color: AppColorScheme.onBadge,
          ),
        ),
      ),
    );
  }
}

/// A small text chip over a card image, like "6h 12m left" on an audiobook.
class BookProgressChip extends StatelessWidget {
  final String label;

  const BookProgressChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColorScheme.scrim.withValues(alpha: 0.78),
        borderRadius: AppRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: AppColorScheme.onBadge,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
