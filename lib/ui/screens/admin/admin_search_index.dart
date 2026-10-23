import 'package:server_core/server_core.dart';

import '../../../l10n/app_localizations.dart';
import 'admin_nav.dart';
import 'emby/emby_config_pages.dart';
import 'search/library_search_entries.dart';
import 'search/livetv_search_entries.dart';
import 'search/overview_search_entries.dart';
import 'search/playback_search_entries.dart';
import 'search/system_search_entries.dart';

/// One thing the admin search can find: a page, or a setting on a page.
class AdminSearchEntry {
  const AdminSearchEntry({
    required this.pageId,
    required this.label,
    this.section,
    this.anchor,
    this.servers,
  });

  final String pageId;
  final String Function(AppLocalizations l10n) label;
  final String Function(AppLocalizations l10n)? section;

  /// The [AdminSettingAnchor] id of the row, null for a whole page.
  final String? anchor;

  /// The servers whose page has this row, every server when null.
  final Set<ServerType>? servers;

  String where(AppLocalizations l10n) {
    final page = adminPageById(pageId);
    final parts = [
      if (page != null) adminGroupOf(page).title(l10n),
      if (page != null) page.title(l10n),
      if (section != null) section!(l10n),
    ];
    return parts.join(' · ');
  }
}

/// [AdminSearchEntry.servers] for a row only one server has.
const jellyfinOnly = {ServerType.jellyfin};
const embyOnly = {ServerType.emby};

/// A settings row on [page]. Its anchor is `<page>.<key>`, the id the page
/// gives the row's AdminSettingAnchor.
AdminSearchEntry adminSettingRow(
  String page,
  String key,
  String Function(AppLocalizations l10n) label,
  String Function(AppLocalizations l10n) section, {
  Set<ServerType>? servers,
}) => AdminSearchEntry(
  pageId: page,
  label: label,
  section: section,
  anchor: '$page.$key',
  servers: servers,
);

/// Every page, then the settings rows, one file per group under search/.
/// Keep the anchor ids in step with the pages.
List<AdminSearchEntry> adminSearchEntries(ServerType server) => [
  for (final group in adminGroups)
    for (final page in group.pagesOn(server))
      AdminSearchEntry(pageId: page.id, label: page.title),
  for (final entry in [
    ...overviewSearchEntries,
    ...librarySearchEntries,
    ...livetvSearchEntries,
    ...playbackSearchEntries,
    ...systemSearchEntries,
  ])
    if (adminPageById(entry.pageId)?.availableOn(server) ?? false)
      if (server != ServerType.emby || !embyOwnPages.contains(entry.pageId))
        if (entry.servers?.contains(server) ?? true) entry,
  if (server == ServerType.emby) ...embySearchEntries,
];

/// Every word of [query] has to appear in the label or where it lives.
List<AdminSearchEntry> matchAdminSearch(
  List<AdminSearchEntry> entries,
  String query,
  AppLocalizations l10n,
) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final matches = <AdminSearchEntry>[];
  for (final entry in entries) {
    final page = adminPageById(entry.pageId);
    final text = [
      entry.label(l10n),
      entry.where(l10n),
      if (entry.anchor == null && page != null) page.description(l10n),
    ].join(' ').toLowerCase();
    if (words.every(text.contains)) matches.add(entry);
  }
  return matches.take(30).toList();
}
