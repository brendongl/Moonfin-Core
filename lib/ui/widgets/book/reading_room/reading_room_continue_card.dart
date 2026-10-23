import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../focus/glass_focus_halo.dart';
import 'reading_room_tiles.dart';

/// A large Continue card: the cover, the format, the title in the serif,
/// the author, how far along it is and a Read or Listen button. The card
/// opens the title's details and the button picks up where it left off.
class ReadingRoomContinueCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool isAudio;
  final double progress;
  final String? meta;
  final String ctaLabel;
  final bool large;

  /// D-pad focus on the card itself.
  final bool focused;

  /// D-pad focus on the button, a step down from the card.
  final bool buttonFocused;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onLongPress;

  const ReadingRoomContinueCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.isAudio,
    required this.progress,
    required this.ctaLabel,
    required this.onTap,
    required this.onPlay,
    this.imageUrl,
    this.meta,
    this.large = false,
    this.focused = false,
    this.buttonFocused = false,
    this.onLongPress,
  });

  static double heightFor({required bool large}) => large ? 216 : 168;

  @override
  Widget build(BuildContext context) {
    final onSurface = AppColorScheme.onSurface;
    final accent = AppColorScheme.accent;
    final coverWidth = large ? 120.0 : 84.0;
    final coverHeight = isAudio ? coverWidth : coverWidth * 1.5;

    final button = Semantics(
      container: true,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPlay,
        child: GlassFocusHalo(
          focused: buttonFocused,
          scale: 1.06,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: large ? 40 : 36,
            padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: AppRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 20,
                  color: AppColorScheme.onAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  ctaLabel,
                  style: TextStyle(
                    fontSize: large ? 14 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppColorScheme.onAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassFocusHalo(
        focused: focused,
        scale: 1.02,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: heightFor(large: large),
          padding: EdgeInsets.all(large ? 18 : 14),
          decoration: BoxDecoration(
            color: AppColorScheme.surface,
            borderRadius: AppRadius.circular(18),
            border: Border.all(color: onSurface.withValues(alpha: 0.07)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.circular(large ? 8 : 6),
                child: SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                  child: readingRoomCover(imageUrl, isAudio: isAudio),
                ),
              ),
              SizedBox(width: large ? 20 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: large ? 11 : 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: readingRoomSerif(large ? 22 : 17),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: large ? 14 : 12.5,
                          color: onSurface.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                    const Spacer(),
                    ClipRRect(
                      borderRadius: AppRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: onSurface.withValues(alpha: 0.14),
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            meta ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        button,
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
