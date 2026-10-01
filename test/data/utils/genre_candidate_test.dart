import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/utils/genre_browse_utils.dart';

void main() {
  test('keeps a genre the server sent without any counts', () {
    // Emby 4.9.5 /Genres leaves every count out, even with Fields=ItemCounts.
    expect(
      isBrowsableGenreCandidate(
        {'Id': '1', 'Name': 'Drama', 'Type': 'Genre'},
        normalizedItemTypes: kBrowsableGenreItemTypes,
      ),
      isTrue,
    );
  });

  test('drops a genre whose counts say it is empty', () {
    expect(
      isBrowsableGenreCandidate(
        {'Name': 'Polka', 'MovieCount': 0, 'SeriesCount': 0},
        normalizedItemTypes: kBrowsableGenreItemTypes,
      ),
      isFalse,
    );
  });

  test('keeps a genre with counted items', () {
    expect(
      isBrowsableGenreCandidate(
        {'Name': 'Drama', 'MovieCount': 3},
        normalizedItemTypes: kBrowsableGenreItemTypes,
      ),
      isTrue,
    );
  });
}
