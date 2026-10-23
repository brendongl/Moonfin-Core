import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';

/// What a book library shows when it holds nothing to read or listen to.
class BookEmptyState extends StatelessWidget {
  const BookEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onSurface = AppColorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noBooksFound,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.85),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noBooksFoundDescription,
              style: TextStyle(
                fontSize: 14,
                color: onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
