import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../widgets/adaptive/adaptive_glass.dart';
import 'admin_settings_search.dart';

/// Shared presentation helpers for the admin form screens. They wrap the
/// existing raw-map form logic in an inset-grouped glass aesthetic without
/// changing how callers read or write their config maps.

Widget adminScreenHeader(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData? icon,
}) {
  final onSurface = AppColorScheme.onSurface;
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.spaceLg),
    child: Row(
      children: [
        if (icon != null) ...[
          _accentIconChip(icon),
          const SizedBox(width: AppSpacing.spaceMd),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Widget adminSectionLabel(
  BuildContext context,
  String text, {
  IconData? icon,
}) {
  final accent = AppColorScheme.accent;
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.spaceXs,
      AppSpacing.spaceXl,
      AppSpacing.spaceXs,
      AppSpacing.spaceSm,
    ),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: accent.withValues(alpha: 0.9),
          ),
        ),
      ],
    ),
  );
}

/// A [adminSectionLabel] followed by a glass card grouping [children].
Widget adminSection(
  BuildContext context, {
  required String title,
  IconData? icon,
  required List<Widget> children,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      adminSectionLabel(context, title, icon: icon),
      adminGlassGroup(context, children: children),
    ],
  );
}

/// A solid (non-blurred) translucent rounded card. Use for rows inside a
/// scrollable `ListView.builder` instead of [adminGlassGroup], which would add
/// a `BackdropFilter` per row and janks long lists on glass themes.
Widget adminListCard({required Widget child, EdgeInsetsGeometry? margin}) {
  return Container(
    margin: margin,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColorScheme.onSurface.withValues(alpha: 0.04),
      borderRadius: AppRadius.circular(18),
      border: Border.all(
        color: AppColorScheme.onSurface.withValues(alpha: 0.08),
        width: 0.5,
      ),
    ),
    child: child,
  );
}

/// Groups [children] into a rounded translucent card with hairline dividers.
Widget adminGlassGroup(
  BuildContext context, {
  required List<Widget> children,
}) {
  final rows = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) rows.add(_hairline());
    rows.add(children[i]);
  }
  return adaptiveGlass(
    cornerRadius: 18,
    blur: 22,
    tint: AppColorScheme.onSurface.withValues(alpha: 0.04),
    fallbackColor: AppColorScheme.surface.withValues(alpha: 0.55),
    // Rows paint their hover and press highlight on the nearest Material.
    // Without this one, that's the panel under the pane, and the square
    // highlight shows through past the rounded corners.
    child: Material(
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.spaceXs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    ),
  );
}

Widget _hairline() => Padding(
      padding: const EdgeInsets.only(left: AppSpacing.spaceLg),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColorScheme.onSurface.withValues(alpha: 0.10),
      ),
    );

InputDecoration adminInputDecoration({
  String? label,
  String? hint,
  String? helper,
  String? suffixText,
  Widget? suffixIcon,
}) {
  final onSurface = AppColorScheme.onSurface;
  final accent = AppColorScheme.accent;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: AppRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    filled: true,
    fillColor: onSurface.withValues(alpha: 0.05),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.spaceLg,
      vertical: 16,
    ),
    floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w600),
    border: border(Colors.transparent, 0),
    enabledBorder: border(onSurface.withValues(alpha: 0.08), 1),
    focusedBorder: border(accent, 1.6),
    suffixText: suffixText,
    suffixIcon: suffixIcon,
  );
}

/// Dropdown of `(code, displayName)` pairs with a leading "default" option.
/// Dedupes by code (the localization lists can repeat codes) and preserves an
/// unknown [current] value so saving never silently drops it. Falls back to a
/// free-text field when [rawItems] is empty (older servers expose no list).
Widget adminCodeDropdown({
  required String label,
  required String defaultLabel,
  required String current,
  required Iterable<(String?, String?)> rawItems,
  required ValueChanged<String?> onChanged,
  String? helper,
  String? anchor,
}) {
  final seen = <String>{};
  final items = <(String, String)>[];
  for (final e in rawItems) {
    final code = e.$1;
    final name = e.$2;
    // Jellyfin 12.2 lists 302 cultures with an empty two-letter code. A
    // second '' item next to the default trips DropdownButton's
    // one-item-per-value assert.
    if (code == null || code.isEmpty || name == null) continue;
    if (!seen.add(code)) continue;
    items.add((code, name));
  }
  if (items.isEmpty) {
    return adminFieldRow(
      label: label,
      helper: helper,
      anchor: anchor,
      child: TextFormField(
        initialValue: current,
        decoration: adminInputDecoration(),
        onChanged: onChanged,
      ),
    );
  }
  final hasCurrent = current.isEmpty || items.any((e) => e.$1 == current);
  return adminFieldRow(
    label: label,
    helper: helper,
    anchor: anchor,
    child: DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: adminInputDecoration(),
      items: [
        DropdownMenuItem(value: '', child: Text(defaultLabel)),
        ...items.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))),
        if (!hasCurrent) DropdownMenuItem(value: current, child: Text(current)),
      ],
      onChanged: onChanged,
    ),
  );
}

Widget adminSwitchRow({
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
  String? anchor,
}) {
  final row = SwitchListTile.adaptive(
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: AppColorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
    value: value,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.spaceLg,
      vertical: 2,
    ),
    onChanged: onChanged,
  );
  return anchor == null ? row : AdminSettingAnchor(id: anchor, child: row);
}

/// A setting row with the label and its help on the left and the control on
/// the right, stacked when the content is narrower than 720 px. Sits in an
/// [adminGlassGroup] beside switch rows.
Widget adminFieldRow({
  required String label,
  String? helper,
  required Widget child,
  String? anchor,
}) {
  final onSurface = AppColorScheme.onSurface;
  final text = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      if (helper != null) ...[
        const SizedBox(height: 2),
        Text(
          helper,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    ],
  );
  final row = Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.spaceLg,
      vertical: AppSpacing.spaceMd,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 720
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 10, child: text),
                const SizedBox(width: AppSpacing.spaceXl),
                Expanded(flex: 12, child: child),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: AppSpacing.spaceSm), child],
            ),
    ),
  );
  return anchor == null ? row : AdminSettingAnchor(id: anchor, child: row);
}

/// Full-width accent action button with a spinner while [saving].
Widget adminSaveButton({
  required String label,
  required bool saving,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: saving ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColorScheme.accent,
        foregroundColor: AppColorScheme.onAccent,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.circular(14)),
      ),
      child: saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ),
  );
}

Widget _accentIconChip(IconData icon) {
  final accent = AppColorScheme.accent;
  return Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      borderRadius: AppRadius.circular(13),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.30),
          accent.withValues(alpha: 0.14),
        ],
      ),
      border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
    ),
    child: Icon(icon, size: 24, color: accent),
  );
}
