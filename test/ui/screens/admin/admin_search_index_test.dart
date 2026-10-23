import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/admin/admin_search_index.dart';
import 'package:server_core/server_core.dart';

void main() {
  test('rows on a shared page follow the server that has them', () {
    Set<String?> anchors(ServerType server) => {
      for (final entry in adminSearchEntries(server)) entry.anchor,
    };
    const jellyfinRows = {
      'branding.SplashscreenEnabled',
      'settings.QuickConnectAvailable',
      'settings.SlowResponseThresholdMs',
      'metadata.DummyChapterDuration',
      'live-tv.SaveRecordingNFO',
    };
    const embyRows = {
      'settings.IsInMaintenanceMode',
      'settings.EnableAutomaticRestart',
      'settings.BannerText',
      'metadata.UseFileCreationTimeForDateAdded',
      'live-tv.WakeServer',
    };

    final emby = anchors(ServerType.emby);
    final jellyfin = anchors(ServerType.jellyfin);
    expect(emby, containsAll(embyRows));
    expect(emby.intersection(jellyfinRows), isEmpty);
    expect(jellyfin, containsAll(jellyfinRows));
    expect(jellyfin.intersection(embyRows), isEmpty);
    // Rows both servers have stay in both.
    for (final shared in ['branding.CustomCss', 'settings.ServerName']) {
      expect(emby, contains(shared));
      expect(jellyfin, contains(shared));
    }
  });
}
