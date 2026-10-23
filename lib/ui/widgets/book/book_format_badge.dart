import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';

/// Small glyph chip marking a card as a comic. Solid scrim colors (no glass)
/// so a grid of cards stays cheap on TV GPUs.
class BookComicBadge extends StatelessWidget {
  const BookComicBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).bookFormatComic,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColorScheme.scrim.withValues(alpha: 0.72),
          borderRadius: AppRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Icon(
            Icons.auto_stories_rounded,
            size: 12,
            color: AppColorScheme.onBadge,
          ),
        ),
      ),
    );
  }
}

/// Formats a duration as a short "6h 12m" / "42m" label for chips.
String formatBookDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// How far along a title is, "34% read" for books and "6h 12m left" for
/// audiobooks, or an audiobook's whole runtime before it's started. Null when
/// there's nothing to show.
String? bookProgressMeta(
  AppLocalizations l10n, {
  required bool isAudiobook,
  required double playedPercentage,
  Duration? remaining,
}) {
  if (isAudiobook) {
    if (remaining == null) return null;
    final label = formatBookDuration(remaining);
    return playedPercentage > 0 ? l10n.bookTimeLeft(label) : label;
  }
  if (playedPercentage <= 0) return null;
  return l10n.bookPercentRead(playedPercentage.round());
}
