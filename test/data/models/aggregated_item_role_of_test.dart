import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';

AggregatedItem itemWith(Map<String, dynamic> raw) =>
    AggregatedItem(id: 'i1', serverId: 'srv', rawData: raw);

void main() {
  test('reads the role of the matching person, skipping a blank credit', () {
    // Someone who directed and acted in a title is listed once per credit.
    final item = itemWith({
      'People': [
        {'Id': 'p2', 'Role': 'Fry', 'Type': 'Actor'},
        {'Id': 'p1', 'Role': '', 'Type': 'Director'},
        {'Id': 'p1', 'Role': ' Bender (voice) ', 'Type': 'Actor'},
      ],
    });

    expect(item.roleOf('p1'), 'Bender (voice)');
    expect(item.roleOf('p3'), isNull);
  });

  test('several roles on separate lines read as one', () {
    final item = itemWith({
      'People': [
        {'Id': 'p1', 'Role': 'Wakka\nKimahri\n', 'Type': 'Actor'},
      ],
    });

    expect(item.roleOf('p1'), 'Wakka, Kimahri');
  });

  test('no People or no role is null', () {
    expect(itemWith(const {}).roleOf('p1'), isNull);
    expect(
      itemWith({
        'People': [
          {'Id': 'p1', 'Type': 'Director'},
        ],
      }).roleOf('p1'),
      isNull,
    );
  });
}
