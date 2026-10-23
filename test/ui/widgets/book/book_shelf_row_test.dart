import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/book/book_shelf_row.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';

void main() {
  const row = HomeRow(
    id: 'resume',
    title: 'Continue Reading',
    rowType: HomeRowType.resume,
    items: [
      AggregatedItem(
        id: 'b1',
        serverId: 's1',
        rawData: {'Id': 'b1', 'Name': 'Dune', 'Type': 'Book'},
      ),
    ],
  );

  Future<void> pumpRow(
    WidgetTester tester,
    double leadingInset, {
    void Function(AggregatedItem item)? onItemTap,
    void Function(AggregatedItem item)? onItemPlay,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BookShelfRow(
            row: row,
            title: row.title,
            hubKey: 'books_resume',
            rowKey: GlobalKey<LockedFocusRowState<AggregatedItem>>(),
            onItemTap: onItemTap ?? (_) {},
            onItemPlay: onItemPlay ?? (_) {},
            imageUrlFor: (_) => null,
            leadingInset: leadingInset,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the leading inset moves the title and first tile together', (
    tester,
  ) async {
    await pumpRow(tester, 16);
    final item = tester.getTopLeft(find.text('Dune')).dx;
    expect(tester.getTopLeft(find.text('Continue Reading')).dx, 16);

    await pumpRow(tester, 60);
    expect(tester.getTopLeft(find.text('Continue Reading')).dx, 60);
    expect(tester.getTopLeft(find.text('Dune')).dx, item + 44);
  });

  testWidgets('only the play button reads, the tile opens the details', (
    tester,
  ) async {
    final opened = <String>[];
    final played = <String>[];
    await pumpRow(
      tester,
      16,
      onItemTap: (item) => opened.add(item.id),
      onItemPlay: (item) => played.add(item.id),
    );

    await tester.tap(find.text('Dune'));
    expect(opened, ['b1']);
    expect(played, isEmpty);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(played, ['b1']);
    expect(opened, ['b1']);

    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byIcon(Icons.play_arrow_rounded)),
      isSemantics(
        label: 'Continue Reading',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}
