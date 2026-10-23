import '../admin_search_index.dart';

/// Search entries for the overview pages. Each anchor matches an
/// AdminSettingAnchor id on the page. The three server actions share one.
final List<AdminSearchEntry> overviewSearchEntries = [
  adminSettingRow('dashboard', 'ServerActions', (l) => l.adminScanAllLibraries,
      (l) => l.adminServerActions),
  adminSettingRow('dashboard', 'ServerActions', (l) => l.adminRestartServer,
      (l) => l.adminServerActions),
  adminSettingRow('dashboard', 'ServerActions', (l) => l.adminShutdownServer,
      (l) => l.adminServerActions),
  adminSettingRow('dashboard', 'ServerPaths', (l) => l.adminServerPaths,
      (l) => l.adminServerPaths),
];
