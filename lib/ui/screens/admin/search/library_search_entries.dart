import '../admin_search_index.dart';

/// Search entries for the library pages. Each anchor matches an
/// AdminSettingAnchor id on the page. The per-library and per-item editors
/// have no page of their own to open, so their rows aren't listed.
final List<AdminSearchEntry> librarySearchEntries = [
  // Display.
  adminSettingRow('display', 'UseFileCreationTimeForDateAdded',
      (l) => l.adminLibDateAddedLabel, (l) => l.adminLibDateAddedSection),
  adminSettingRow('display', 'EnableFolderView', (l) => l.adminLibFolderView,
      (l) => l.adminLibDisplaySection),
  adminSettingRow('display', 'DisplaySpecialsWithinSeasons',
      (l) => l.adminLibSpecialsInSeasons, (l) => l.adminLibDisplaySection),
  adminSettingRow('display', 'EnableGroupingMoviesIntoCollections',
      (l) => l.adminLibGroupMovies, (l) => l.adminLibDisplaySection),
  adminSettingRow('display', 'EnableGroupingShowsIntoCollections',
      (l) => l.adminLibGroupShows, (l) => l.adminLibDisplaySection),
  adminSettingRow('display', 'EnableExternalContentInSuggestions',
      (l) => l.adminLibExternalSuggestions, (l) => l.adminLibDisplaySection),
  // Metadata.
  adminSettingRow('metadata', 'PreferredMetadataLanguage',
      (l) => l.adminGeneralMetadataLanguage,
      (l) => l.adminLibMetadataLangSection),
  adminSettingRow('metadata', 'MetadataCountryCode', (l) => l.adminGeneralMetadataCountry,
      (l) => l.adminLibMetadataLangSection),
  // Emby has no Display page, so it keeps these on Metadata.
  adminSettingRow('metadata', 'UseFileCreationTimeForDateAdded',
      (l) => l.adminLibDateAddedLabel, (l) => l.adminLibDisplaySection,
      servers: embyOnly),
  adminSettingRow('metadata', 'EnableExternalContentInSuggestions',
      (l) => l.adminLibExternalSuggestions, (l) => l.adminLibDisplaySection,
      servers: embyOnly),
  adminSettingRow('metadata', 'DummyChapterDuration',
      (l) => l.adminLibDummyChapterDuration, (l) => l.adminLibChaptersSection,
      servers: jellyfinOnly),
  adminSettingRow('metadata', 'ChapterImageResolution',
      (l) => l.adminLibChapterImageResolution,
      (l) => l.adminLibChaptersSection, servers: jellyfinOnly),
  // NFO.
  adminSettingRow('nfo', 'UserId', (l) => l.adminLibKodiUser, (l) => l.adminDrawerNfo),
  adminSettingRow('nfo', 'SaveImagePathsInNfo', (l) => l.adminLibSaveImagePaths,
      (l) => l.adminDrawerNfo),
  adminSettingRow('nfo', 'EnablePathSubstitution', (l) => l.adminLibPathSubstitution,
      (l) => l.adminDrawerNfo),
  adminSettingRow('nfo', 'EnableExtraThumbsDuplication', (l) => l.adminLibExtraThumbs,
      (l) => l.adminDrawerNfo),
];
