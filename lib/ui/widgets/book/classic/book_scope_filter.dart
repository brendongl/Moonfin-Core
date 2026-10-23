import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/viewmodels/book_browse_view_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../util/focus/dpad_keys.dart';
import '../../focus/glass_focus_halo.dart';
import '../book_glass.dart';
import '../book_scope_filter.dart' show bookScopeLabel;

/// The Classic format filter for mixed libraries, a pill with a sliding
/// selected segment. It's glass on glass tiers and a solid surface with an
/// accent thumb otherwise. The whole pill is one focus stop, and Left and
/// Right move the selection while it's focused.
class BookScopeFilter extends StatefulWidget {
  final BookScope value;
  final ValueChanged<BookScope> onChanged;
  final List<BookScope>? availableScopes;
  final FocusNode? focusNode;

  /// Up and down D-pad presses from the pill. Returns true when handled.
  final bool Function(bool isUp)? onVerticalNavigation;

  const BookScopeFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.availableScopes,
    this.focusNode,
    this.onVerticalNavigation,
  });

  @override
  State<BookScopeFilter> createState() => _BookScopeFilterState();
}

class _BookScopeFilterState extends State<BookScopeFilter> {
  List<BookScope> get _scopes => widget.availableScopes ?? BookScope.values;

  FocusNode? _ownedNode;
  FocusNode get _node =>
      widget.focusNode ?? (_ownedNode ??= FocusNode(debugLabel: 'BookScopeFilter'));

  bool _focused = false;

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final scopes = _scopes;
    final index = scopes.indexOf(widget.value);
    if (key.isLeftKey) {
      if (index > 0) widget.onChanged(scopes[index - 1]);
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index >= 0 && index < scopes.length - 1) {
        widget.onChanged(scopes[index + 1]);
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && (key.isUpKey || key.isDownKey)) {
      final handled = widget.onVerticalNavigation?.call(key.isUpKey) ?? false;
      return handled ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final glass = bookGlassEligible;
    final onSurface = AppColorScheme.onSurface;
    final accent = AppColorScheme.accent;
    final scopes = _scopes;
    final selectedIndex = scopes.indexOf(widget.value);
    final effectiveIndex = selectedIndex >= 0 ? selectedIndex : 0;

    final thumbColor = glass
        ? onSurface.withValues(alpha: 0.22)
        : accent;
    final selectedTextColor = glass ? onSurface : AppColorScheme.onAccent;

    final track = Stack(
      children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment(
            scopes.length <= 1
                ? 0
                : -1 + effectiveIndex * (2 / (scopes.length - 1)),
            0,
          ),
          child: FractionallySizedBox(
            widthFactor: scopes.isEmpty ? 1 : 1 / scopes.length,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: thumbColor,
                borderRadius: AppRadius.circular(999),
                border: glass
                    ? Border.all(
                        color: onSurface.withValues(alpha: 0.25),
                        width: 0.5,
                      )
                    : null,
              ),
            ),
          ),
        ),
        Row(
          children: [
            for (final scope in scopes)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onChanged(scope),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(
                      bookScopeLabel(l10n, scope),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: scope == widget.value
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: scope == widget.value
                            ? selectedTextColor
                            : onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    return Focus(
      focusNode: _node,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (has) => setState(() => _focused = has),
      child: GlassFocusHalo(
        focused: _focused,
        scale: 1.0,
        borderRadius: BorderRadius.circular(999),
        child: bookGlassOrSolid(
          cornerRadius: 999,
          blur: 12,
          fallbackColor: onSurface.withValues(alpha: 0.08),
          context: context,
          child: SizedBox(height: 34, child: track),
        ),
      ),
    );
  }
}
