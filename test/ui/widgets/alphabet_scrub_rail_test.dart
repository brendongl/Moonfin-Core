import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/alphabet_scrub_rail.dart';

const _bubble = ValueKey('alphabet_scrub_bubble');

Future<Rect> _pumpRail(
  WidgetTester tester,
  List<String> fired, {
  double height = 540,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: kAlphabetScrubRailWidth,
            height: height,
            child: AlphabetScrubRail(onLetter: fired.add),
          ),
        ),
      ),
    ),
  );
  return tester.getRect(find.byType(AlphabetScrubRail));
}

Offset _letterCenter(Rect rail, int index) => Offset(
  rail.center.dx,
  rail.top + (index + 0.5) * rail.height / kAlphabetLetters.length,
);

void main() {
  testWidgets('dragging down the rail fires each letter once, in order', (
    tester,
  ) async {
    final fired = <String>[];
    final rail = await _pumpRail(tester, fired);
    final step = rail.height / kAlphabetLetters.length;

    final gesture = await tester.startGesture(_letterCenter(rail, 0));
    await tester.pump();
    for (var i = 1; i < kAlphabetLetters.length; i++) {
      await gesture.moveBy(Offset(0, step / 2));
      await tester.pump();
      await gesture.moveBy(Offset(0, step / 2));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(fired, kAlphabetLetters);
  });

  testWidgets('the magnified letter shows only while the finger is down', (
    tester,
  ) async {
    final fired = <String>[];
    final rail = await _pumpRail(tester, fired);
    expect(find.byKey(_bubble), findsNothing);

    final gesture = await tester.startGesture(_letterCenter(rail, 13));
    await tester.pump();
    expect(find.byKey(_bubble), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_bubble), matching: find.text('M')),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byKey(_bubble)).right,
      lessThan(rail.left),
      reason: 'it sits beside the finger, not under it',
    );

    await gesture.moveTo(_letterCenter(rail, 20));
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(_bubble), matching: find.text('T')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump();
    expect(find.byKey(_bubble), findsNothing);
    expect(fired, ['M', 'T']);
  });

  testWidgets('a short rail draws fewer letters but lands on every one', (
    tester,
  ) async {
    final fired = <String>[];
    final rail = await _pumpRail(tester, fired, height: 140);

    expect(find.text('#'), findsOneWidget);
    expect(find.text('Z'), findsOneWidget);
    expect(find.text('B'), findsNothing, reason: 'condensed to dots');

    for (var i = 0; i < kAlphabetLetters.length; i++) {
      final gesture = await tester.startGesture(_letterCenter(rail, i));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }
    expect(fired, kAlphabetLetters);
  });

  testWidgets('a screen reader steps through the letters one at a time', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final fired = <String>[];
    await _pumpRail(tester, fired);

    final rail = find.semantics.byLabel('Jump to letter');
    expect(
      tester.getSemantics(find.byType(AlphabetScrubRail)),
      matchesSemantics(
        label: 'Jump to letter',
        value: '#',
        increasedValue: 'A',
        isSlider: true,
        hasIncreaseAction: true,
      ),
    );

    tester.semantics.performAction(rail, SemanticsAction.increase);
    await tester.pump();
    tester.semantics.performAction(rail, SemanticsAction.increase);
    await tester.pump();
    tester.semantics.performAction(rail, SemanticsAction.decrease);
    await tester.pump();

    expect(fired, ['A', 'B', 'A']);
    expect(
      tester.getSemantics(find.byType(AlphabetScrubRail)),
      matchesSemantics(
        label: 'Jump to letter',
        value: 'A',
        increasedValue: 'B',
        decreasedValue: '#',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    handle.dispose();
  });
}
