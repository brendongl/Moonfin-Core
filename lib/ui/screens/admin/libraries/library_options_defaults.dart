/// LibraryOptions helpers shared by Add Library and the library editor.
///
/// Every provider list comes from `/Libraries/AvailableOptions`, and an unset
/// list means the providers marked DefaultEnabled. Writing those effective
/// lists into the options lets the pages read and edit them directly.
library;

/// Per-type provider lists: (available key, enabled key, order key).
const _typeProviderKeys = [
  ('MetadataFetchers', 'MetadataFetchers', 'MetadataFetcherOrder'),
  ('ImageFetchers', 'ImageFetchers', 'ImageFetcherOrder'),
  ('SimilarItemProviders', 'SimilarItemProviders', 'SimilarItemProviderOrder'),
];

/// Library-wide provider lists: (available key, disabled key, order key).
const _globalProviderKeys = [
  ('SubtitleFetchers', 'DisabledSubtitleFetchers', 'SubtitleFetcherOrder'),
  ('LyricFetchers', 'DisabledLyricFetchers', 'LyricFetcherOrder'),
  // Emby spells its lyric keys with "Lyrics".
  ('LyricsFetchers', 'DisabledLyricsFetchers', 'LyricsFetcherOrder'),
  (
    'MediaSegmentProviders',
    'DisabledMediaSegmentProviders',
    'MediaSegmentProviderOrder',
  ),
];

/// The options a new library gets when nothing is touched. The server stores
/// a new library's options as sent, so this is the full set. Emby sends its
/// own in `DefaultLibraryOptions`.
Map<String, dynamic> newLibraryOptions(Map<String, dynamic> available) =>
    seedLibraryOptions(switch (available['DefaultLibraryOptions']) {
      final Map defaults => Map<String, dynamic>.from(defaults),
      _ => _jellyfinNewLibraryOptions(),
    }, available);

Map<String, dynamic> _jellyfinNewLibraryOptions() => {
      'Enabled': true,
      'EnablePhotos': true,
      'EnableRealtimeMonitor': true,
      'EnableLUFSScan': true,
      'ExtractTrickplayImagesDuringLibraryScan': false,
      'SaveTrickplayWithMedia': false,
      'EnableTrickplayImageExtraction': false,
      'ExtractChapterImagesDuringLibraryScan': false,
      'EnableChapterImageExtraction': false,
      'EnableInternetProviders': true,
      'SaveLocalMetadata': false,
      'EnableAutomaticSeriesGrouping': false,
      'PreferredMetadataLanguage': '',
      'MetadataCountryCode': '',
      'SeasonZeroDisplayName': 'Specials',
      'AutomaticRefreshIntervalDays': 0,
      'EnableEmbeddedTitles': false,
      'EnableEmbeddedExtrasTitles': false,
      'EnableEmbeddedEpisodeInfos': false,
      'AllowEmbeddedSubtitles': 'AllowAll',
      'SkipSubtitlesIfEmbeddedSubtitlesPresent': false,
      'SkipSubtitlesIfAudioTrackMatches': false,
      'SaveSubtitlesWithMedia': true,
      'SaveLyricsWithMedia': false,
      'RequirePerfectSubtitleMatch': true,
      'AutomaticallyAddToCollection': false,
      'PreferNonstandardArtistsTag': false,
      'UseCustomTagDelimiters': false,
      'SubtitleDownloadLanguages': <String>[],
      'CustomTagDelimiters': ['/', '|', ';', r'\'],
      'DelimiterWhitelist': <String>[],
      'TypeOptions': <Map<String, dynamic>>[],
    };

/// Writes the effective provider lists into [options] (in place) and returns
/// it. Stored lists win, unset ones take the DefaultEnabled providers, and
/// every order lists the configured names first, then the rest as offered.
Map<String, dynamic> seedLibraryOptions(
  Map<String, dynamic> options,
  Map<String, dynamic> available,
) {
  final savers = libraryProviders(available['MetadataSavers']);
  if (savers.isNotEmpty) {
    options['MetadataSavers'] =
        _strings(options['MetadataSavers']) ?? _defaultEnabled(savers);
  }

  final readers = libraryProviders(available['MetadataReaders']);
  if (readers.isNotEmpty) {
    options['LocalMetadataReaderOrder'] = _ordered(
      readers,
      _strings(options['LocalMetadataReaderOrder']) ?? const [],
    );
  }

  for (final (availKey, disabledKey, orderKey) in _globalProviderKeys) {
    final avail = libraryProviders(available[availKey]);
    if (avail.isEmpty) continue;
    options[orderKey] =
        _ordered(avail, _strings(options[orderKey]) ?? const []);
    options[disabledKey] = _strings(options[disabledKey]) ??
        [
          for (final p in avail)
            if (p['DefaultEnabled'] != true) p['Name'].toString(),
        ];
  }

  final typeOptions = [
    for (final t in (options['TypeOptions'] as List?) ?? const [])
      if (t is Map) Map<String, dynamic>.from(t),
  ];
  for (final availType in libraryProviders(available['TypeOptions'])) {
    final type = availType['Type']?.toString();
    if (type == null) continue;
    for (final (availKey, enabledKey, orderKey) in _typeProviderKeys) {
      final avail = libraryProviders(availType[availKey]);
      if (avail.isEmpty) continue;
      var stored = typeOptions.where((t) => t['Type'] == type).firstOrNull;
      if (stored == null) {
        stored = {'Type': type};
        typeOptions.add(stored);
      }
      stored[orderKey] =
          _ordered(avail, _strings(stored[orderKey]) ?? const []);
      stored[enabledKey] = _strings(stored[enabledKey]) ?? _defaultEnabled(avail);
    }
  }
  options['TypeOptions'] = typeOptions;
  return options;
}

/// [raw]'s provider maps, or none when it isn't a list.
List<Map<String, dynamic>> libraryProviders(Object? raw) => [
  for (final e in (raw is List ? raw : const []))
    if (e is Map) Map<String, dynamic>.from(e),
];

List<String>? _strings(Object? raw) =>
    raw is List ? raw.map((e) => e.toString()).toList() : null;

List<String> _defaultEnabled(List<Map<String, dynamic>> plugins) => [
  for (final p in plugins)
    if (p['DefaultEnabled'] == true) p['Name'].toString(),
];

/// Configured names first, then every other offered provider in offered order.
/// Names the server no longer offers drop out.
List<String> _ordered(List<Map<String, dynamic>> available, List<String> order) {
  final names = [for (final p in available) p['Name']?.toString() ?? ''];
  return [
    for (final n in order)
      if (names.contains(n)) n,
    for (final n in names)
      if (n.isNotEmpty && !order.contains(n)) n,
  ];
}
