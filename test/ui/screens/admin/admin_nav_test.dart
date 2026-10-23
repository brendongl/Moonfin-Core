import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/admin_search_index.dart';
import 'package:server_core/server_core.dart';

void main() {
  test('Emby gets the panel from 4.9', () {
    expect(embyVersionSupported('4.8.10.0'), isFalse);
    expect(embyVersionSupported('4.9.0.42'), isTrue);
    expect(embyVersionSupported('4.10.1.0'), isTrue);
    expect(embyVersionSupported('5.0'), isTrue);
    expect(embyVersionSupported(''), isFalse);
  });

  test('Jellyfin only pages and their search rows stay off Emby', () {
    const jellyfinOnly = {'display', 'resume', 'trickplay', 'repositories'};
    final embyPages = {
      for (final group in adminGroups)
        for (final page in group.pagesOn(ServerType.emby)) page.id,
    };
    expect(embyPages.intersection(jellyfinOnly), isEmpty);
    expect(embyPages, containsAll(['dashboard', 'users', 'plugins']));

    final embySearch = adminSearchEntries(ServerType.emby);
    expect(embySearch.where((e) => jellyfinOnly.contains(e.pageId)), isEmpty);
    expect(
      adminSearchEntries(ServerType.jellyfin).map((e) => e.pageId),
      containsAll(jellyfinOnly),
    );
  });
}
