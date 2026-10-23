import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/admin/widgets/admin_form_styles.dart';

void main() {
  // Jellyfin 12.2 lists hundreds of cultures with an empty two-letter code.
  // With the default ('') selected, a second '' item would trip
  // DropdownButton's one-item-per-value assert.
  testWidgets('a code dropdown leaves out items with an empty code', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: adminCodeDropdown(
            label: 'Language',
            defaultLabel: 'Default',
            current: '',
            rawItems: const [
              ('', 'Invariant Language'),
              ('en', 'English'),
              ('en', 'English (United States)'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    expect(find.text('Invariant Language'), findsNothing);
    expect(find.text('English'), findsWidgets);
  });
}
