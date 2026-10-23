import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/ui/screens/settings/settings_side_panel.dart';

class Capability extends Fake implements PluginSyncService {
  bool installed = true, configured = true, localEnabled = false;
  @override
  bool get pluginAvailable => installed;
  @override
  bool get seerrEnabled => configured;
  @override
  bool get seerrAvailable => installed && configured && localEnabled;
}

void main() {
  test('locally disabled requests can still be re-enabled from settings', () {
    final service = Capability();
    expect(service.seerrAvailable, false);
    expect(sipflixSeerrSettingsAvailable(service), true);
    service.localEnabled = true;
    expect(sipflixSeerrSettingsAvailable(service), true);
    service.configured = false;
    expect(sipflixSeerrSettingsAvailable(service), false);
    service.configured = true;
    service.installed = false;
    expect(sipflixSeerrSettingsAvailable(service), false);
  });
}
