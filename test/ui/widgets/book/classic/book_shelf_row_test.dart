import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/book/classic/book_shelf_row.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';

void main() {
  const row = HomeRow(
    id: 'genres',
    title: 'Genres',
    rowType: HomeRowType.genres,
    items: [
      AggregatedItem(
        id: 'g1',
        serverId: 's1',
        rawData: {'Id': 'g1', 'Name': 'Fantasy', 'Type': 'Genre'},
      ),
    ],
  );

  Future<void> pumpRow(WidgetTester tester, double leadingInset) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BookShelfRow(
            row: row,
            title: row.title,
            variant: BookShelfVariant.chip,
            hubKey: 'books_genres',
            rowKey: GlobalKey<LockedFocusRowState<AggregatedItem>>(),
            onItemTap: (_) {},
            imageUrlFor: (_) => null,
            leadingInset: leadingInset,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the leading inset moves the title and first item together', (
    tester,
  ) async {
    await pumpRow(tester, 16);
    final item = tester.getTopLeft(find.text('Fantasy')).dx;
    expect(tester.getTopLeft(find.text('Genres')).dx, 16);

    await pumpRow(tester, 60);
    expect(tester.getTopLeft(find.text('Genres')).dx, 60);
    expect(tester.getTopLeft(find.text('Fantasy')).dx, item + 44);
  });

  testWidgets('Up from the shelf reaches See all before the shelf above', (
    tester,
  ) async {
    final rowKey = GlobalKey<LockedFocusRowState<AggregatedItem>>();
    final seeAllNode = FocusNode(debugLabel: 'seeAll');
    addTearDown(seeAllNode.dispose);
    final leftUpward = <bool>[];
    var seeAllPressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BookShelfRow(
            row: row,
            title: row.title,
            variant: BookShelfVariant.chip,
            hubKey: 'books_genres',
            rowKey: rowKey,
            onItemTap: (_) {},
            imageUrlFor: (_) => null,
            onSeeAll: () => seeAllPressed++,
            seeAllFocusNode: seeAllNode,
            onVerticalNavigation: (isUp) {
              leftUpward.add(isUp);
              return true;
            },
          ),
        ),
      ),
    );
    rowKey.currentState!.requestFocusFromMemory();
    await tester.pumpAndSettle();
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focused(), 'seeAll');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(seeAllPressed, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(), 'LockedFocusRow:books_genres');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(leftUpward, [true]);
  });
}
