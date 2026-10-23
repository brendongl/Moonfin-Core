import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart';

// Issue #1874: a button count the user picked caps series and seasons the
// same as movies, instead of the series row showing every everyday button.
void main() {
  bool twoColumn(
    String type, {
    int buttonLimit = 0,
    bool isModernMobile = false,
    bool overflowAsMenu = false,
    bool userArranged = false,
  }) => DetailActionButtonsState.usesTwoColumnLayout(
    itemType: type,
    isModernMobile: isModernMobile,
    overflowAsMenu: overflowAsMenu,
    buttonLimit: buttonLimit,
    userArranged: userArranged,
  );

  test('series and seasons keep the two-column row on Auto', () {
    expect(twoColumn('Series'), isTrue);
    expect(twoColumn('Season'), isTrue);
  });

  test('a picked count sends series and seasons through the count split', () {
    expect(twoColumn('Series', buttonLimit: 1), isFalse);
    expect(twoColumn('Season', buttonLimit: 4), isFalse);
    expect(twoColumn('Series', buttonLimit: -1), isFalse);
  });

  test('an arranged order sends series and seasons through the count split', () {
    expect(twoColumn('Series', userArranged: true), isFalse);
    expect(twoColumn('Season', userArranged: true), isFalse);
  });

  test('movies, the Modern mobile layout and Spotlight never use it', () {
    expect(twoColumn('Movie'), isFalse);
    expect(twoColumn('Series', isModernMobile: true), isFalse);
    expect(twoColumn('Series', overflowAsMenu: true), isFalse);
  });
}
