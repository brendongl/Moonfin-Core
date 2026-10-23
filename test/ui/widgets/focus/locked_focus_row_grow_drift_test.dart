import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/focus/hub_focus_memory.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';

void main() {
  testWidgets('a burst of presses still parks the focused card at the start', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    HubFocusMemory.set('drift', 0);
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: LockedFocusRow<int>(
          items: List.generate(30, (i) => i),
          hubKey: 'drift',
          itemExtent: 40,
          height: 40,
          focusNode: node,
          // Grows on focus like a Modern card, slower than the scroll, so the
          // first card scrolls out of the cache before it has shrunk back.
          itemBuilder: (context, item, index, isFocused) => AnimatedSize(
            duration: const Duration(milliseconds: 600),
            alignment: Alignment.centerLeft,
            child: SizedBox(
              key: ValueKey('card-$index'),
              width: isFocused ? 120 : 40,
              height: 40,
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();

    for (var i = 0; i < 15; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(const ValueKey('card-15'))).dx, 0);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('growing cards keep the padded leading margin in $direction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hubKey = 'padded-drift-$direction';
      HubFocusMemory.set(hubKey, 0);
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: LockedFocusRow<int>(
              items: List.generate(30, (i) => i),
              hubKey: hubKey,
              itemExtent: 40,
              itemSpacing: 6,
              height: 40,
              leadingPadding: 24,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              focusNode: node,
              itemBuilder: (context, item, index, focused) => AnimatedSize(
                duration: const Duration(milliseconds: 600),
                alignment: direction == TextDirection.ltr
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: SizedBox(
                  key: ValueKey('padded-$index'),
                  width: focused ? 120 : 40,
                  height: 40,
                ),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pumpAndSettle();
      final next = direction == TextDirection.ltr
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(next);
      }
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const ValueKey('padded-15')));
      expect(
        direction == TextDirection.ltr ? rect.left : 400 - rect.right,
        closeTo(24, 0.01),
      );
      // Returning to the start must not retain the accumulated drift.
      final previous = direction == TextDirection.ltr
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(previous);
      }
      await tester.pumpAndSettle();
      final first = tester.getRect(find.byKey(const ValueKey('padded-0')));
      expect(
        direction == TextDirection.ltr ? first.left : 400 - first.right,
        closeTo(24, 0.01),
      );
    });
  }
}
