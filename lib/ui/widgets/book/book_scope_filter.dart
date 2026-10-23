import 'package:flutter/widgets.dart';

import '../../../data/viewmodels/book_browse_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../sliding_pill_tabs.dart';

/// The format filter for mixed libraries, drawn with the same pill tabs as
/// Library/Discover.
class BookScopeFilter extends StatelessWidget {
  final BookScope value;
  final ValueChanged<BookScope> onChanged;
  final List<BookScope>? availableScopes;
  final FocusNode? focusNode;

  /// Up and down D-pad presses from the pills. Returns true when handled.
  final bool Function(bool isUp)? onVerticalNavigation;
  final VoidCallback? onExitLeft;
  final VoidCallback? onExitRight;

  const BookScopeFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.availableScopes,
    this.focusNode,
    this.onVerticalNavigation,
    this.onExitLeft,
    this.onExitRight,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopes = availableScopes ?? BookScope.values;
    final selectedIndex = scopes.indexOf(value);
    return SlidingPillTabs(
      labels: [for (final scope in scopes) bookScopeLabel(l10n, scope)],
      selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
      onChanged: (i) => onChanged(scopes[i]),
      focusNode: focusNode,
      onVerticalNavigation: onVerticalNavigation,
      onExitLeft: onExitLeft,
      onExitRight: onExitRight,
    );
  }
}

String bookScopeLabel(AppLocalizations l10n, BookScope scope) =>
    switch (scope) {
      BookScope.all => l10n.all,
      BookScope.books => l10n.books,
      BookScope.audiobooks => l10n.audiobooks,
      BookScope.comics => l10n.comics,
    };
