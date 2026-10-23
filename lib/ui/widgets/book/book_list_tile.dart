import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../focus/focusable_wrapper.dart';
import '../offline_aware_image.dart';

/// One title in the book library's list view: cover, title, author and how
/// far along it is. A single D-pad focus stop.
class BookListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool isAudio;
  final bool isComic;

  /// 0 to 1, null when the title isn't started.
  final double? progress;

  /// "34% read", "6h 12m left" or a runtime.
  final String? meta;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FocusOnKeyEventCallback? onKeyEvent;

  const BookListTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imageUrl,
    this.isAudio = false,
    this.isComic = false,
    this.progress,
    this.meta,
    this.focusNode,
    this.onLongPress,
    this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = AppColorScheme.onSurface;
    final placeholder = ColoredBox(
      color: AppColorScheme.surfaceVariant,
      child: Icon(
        isAudio ? Icons.headphones_rounded : Icons.menu_book_rounded,
        size: 20,
        color: onSurface.withValues(alpha: 0.4),
      ),
    );
    final formatIcon = isAudio
        ? Icons.headphones_rounded
        : (isComic ? Icons.auto_stories_rounded : null);

    return FocusableWrapper(
      focusNode: focusNode,
      borderRadius: 12,
      autoScroll: true,
      disableScale: true,
      enableLongPress: onLongPress != null,
      onSelect: onTap,
      onLongPress: onLongPress,
      onKeyEvent: onKeyEvent,
      child: SizedBox(
        height: 88,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Center(
                  child: ClipRRect(
                    borderRadius: AppRadius.circular(5),
                    child: SizedBox(
                      width: isAudio ? 64 : 48,
                      height: isAudio ? 64 : 72,
                      child: imageUrl == null
                          ? placeholder
                          : OfflineAwareImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => placeholder,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    if (progress != null || meta != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (progress != null) ...[
                            SizedBox(
                              width: 120,
                              child: ClipRRect(
                                borderRadius: AppRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 3,
                                  backgroundColor:
                                      onSurface.withValues(alpha: 0.14),
                                  valueColor: AlwaysStoppedAnimation(
                                    AppColorScheme.accent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (meta != null)
                            Flexible(
                              child: Text(
                                meta!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: onSurface.withValues(alpha: 0.68),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (formatIcon != null) ...[
                const SizedBox(width: 12),
                Icon(
                  formatIcon,
                  size: 18,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
