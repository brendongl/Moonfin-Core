import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/overlay_sheet.dart';

void main() {
  var clock = DateTime(2026, 10, 2, 9);

  setUp(() {
    DialogBackSuppressor.reset();
    DialogBackSuppressor.now = () => clock;
  });

  test('eats the popRoute that follows a handled BACK', () {
    DialogBackSuppressor.markDismissed();
    clock = clock.add(const Duration(milliseconds: 50));
    expect(DialogBackSuppressor.consume(), isTrue);
    expect(DialogBackSuppressor.consume(), isFalse);
  });

  test('a popRoute that never came does not swallow a later BACK', () {
    DialogBackSuppressor.markDismissed();
    clock = clock.add(const Duration(seconds: 5));
    expect(DialogBackSuppressor.consume(), isFalse);
  });
}
