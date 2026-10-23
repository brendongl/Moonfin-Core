import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../admin_nav.dart';
import '../widgets/admin_form_styles.dart';
import 'admin_library_dialogs.dart';
import 'library_options_defaults.dart';

/// Which half of the library options editor to show.
enum LibraryOptionsPart { options, downloaders }

/// LibraryOptions controls for Add Library and the library editor alike.
/// Edits go straight into [options], then [onChanged] runs.
class LibraryOptionsForm extends StatefulWidget {
  const LibraryOptionsForm({
    super.key,
    required this.part,
    required this.options,
    required this.available,
    required this.collectionType,
    required this.cultures,
    required this.countries,
    required this.onChanged,
  });

  final LibraryOptionsPart part;
  final Map<String, dynamic> options;

  /// GET /Libraries/AvailableOptions for the library's type.
  final Map<String, dynamic> available;

  /// Null or empty for a mixed library.
  final String? collectionType;
  final List<Map<String, dynamic>> cultures;
  final List<Map<String, dynamic>> countries;
  final VoidCallback onChanged;

  @override
  State<LibraryOptionsForm> createState() => _LibraryOptionsFormState();
}

class _LibraryOptionsFormState extends State<LibraryOptionsForm> {
  Map<String, dynamic> get _options => widget.options;
  Map<String, dynamic> get _available => widget.available;
  List<Map<String, dynamic>> get _cultures => widget.cultures;
  List<Map<String, dynamic>> get _countries => widget.countries;

  @override
  Widget build(BuildContext context) => switch (widget.part) {
    LibraryOptionsPart.options => _buildOptions(),
    LibraryOptionsPart.downloaders => _buildDownloaders(),
  };

  void _set(String key, Object? value) {
    setState(() => _options[key] = value);
    widget.onChanged();
  }

  /// Applies [change] to the options, then reports the edit.
  void _edit(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  // ---- Visibility by library type ------------------------------------------

  String? get _type {
    final t = widget.collectionType;
    return t == null || t.isEmpty ? null : t;
  }

  bool get _hasSubtitleOptions =>
      const ['tvshows', 'movies', 'musicvideos', 'mixed'].contains(_type);

  /// An existing mixed library has no type and still gets chapter options.
  bool get _hasChapterOptions =>
      _type == null ||
      const ['homevideos', 'movies', 'musicvideos', 'tvshows'].contains(_type);

  bool get _hasEmbeddedTitles =>
      !const ['books', 'boxsets', 'playlists', 'music'].contains(_type);

  /// Rows only Jellyfin has hide on Emby, and each Emby row shows when the
  /// options carry its key.
  bool get _emby => AdminServerScope.isEmby(context);

  bool _has(String key) => _options.containsKey(key);

  bool get _hasResumeOptions =>
      _type == null ||
      const [
        'tvshows',
        'movies',
        'homevideos',
        'musicvideos',
        'mixed',
        'audiobooks',
      ].contains(_type);

  // ---- Downloaders ---------------------------------------------------------

  bool _anyTypeOffers(String key) => libraryProviders(_available['TypeOptions'])
      .any((t) => (t[key] as List?)?.isNotEmpty ?? false);

  List<String> _strings(Object? raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : <String>[];

  Map<String, dynamic>? _typeStored(String type) {
    for (final t in (_options['TypeOptions'] as List?) ?? const []) {
      if (t is Map && t['Type'] == type) return t.cast<String, dynamic>();
    }
    return null;
  }

  Widget _buildDownloaders() {
    final l10n = AppLocalizations.of(context);
    final types = libraryProviders(_available['TypeOptions']);
    final readers = libraryProviders(_available['MetadataReaders']);
    final sections = <Widget>[
      // The readers only show when there's more than one to order.
      if (readers.length > 1)
        _providerSection(
          l10n.adminLibMetadataReaders,
          Icons.folder_copy_outlined,
          _orderList(_options, 'LocalMetadataReaderOrder'),
        ),
      for (final t in types)
        ..._typeSection(t, 'MetadataFetchers', 'MetadataFetcherOrder',
            l10n.adminLibMetadataDownloadersFor(t['Type'].toString()),
            Icons.cloud_download_outlined),
      if (libraryProviders(_available['MetadataSavers']).isNotEmpty)
        _providerSection(
          l10n.adminLibMetadataSavers,
          Icons.save_outlined,
          _enabledList(
            _options,
            'MetadataSavers',
            _strings(_options['MetadataSavers']),
            names: libraryProviders(_available['MetadataSavers'])
                .map((p) => p['Name'].toString())
                .toList(),
          ),
        ),
      for (final t in types)
        ..._typeSection(t, 'ImageFetchers', 'ImageFetcherOrder',
            l10n.adminLibImageFetchersFor(t['Type'].toString()),
            Icons.image_outlined,
            extra: _imageOptionsButton(t, l10n)),
      for (final t in types)
        ..._typeSection(t, 'SimilarItemProviders', 'SimilarItemProviderOrder',
            l10n.adminLibSimilarProvidersFor(t['Type'].toString()),
            Icons.join_inner),
      if (_hasSubtitleOptions)
        ..._globalSection('SubtitleFetchers', 'DisabledSubtitleFetchers',
            'SubtitleFetcherOrder', l10n.adminLibSubtitleDownloaders,
            Icons.subtitles_outlined),
      if (_type == 'music') ...[
        ..._globalSection('LyricFetchers', 'DisabledLyricFetchers',
            'LyricFetcherOrder', l10n.adminLibLyricDownloaders,
            Icons.lyrics_outlined),
        ..._globalSection('LyricsFetchers', 'DisabledLyricsFetchers',
            'LyricsFetcherOrder', l10n.adminLibLyricDownloaders,
            Icons.lyrics_outlined),
      ],
      ..._globalSection('MediaSegmentProviders', 'DisabledMediaSegmentProviders',
          'MediaSegmentProviderOrder', l10n.adminLibMediaSegmentProviders,
          Icons.segment),
    ];

    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l10n.adminLibNoDownloaders, textAlign: TextAlign.center),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }

  Widget _providerSection(String title, IconData icon, List<Widget> rows) =>
      adminSection(context, title: title, icon: icon, children: rows);

  List<Widget> _typeSection(Map<String, dynamic> availType, String enabledKey,
      String orderKey, String title, IconData icon, {Widget? extra}) {
    final stored = _typeStored(availType['Type'].toString());
    if (stored == null || libraryProviders(availType[enabledKey]).isEmpty) {
      return const [];
    }
    return [
      _providerSection(
        title,
        icon,
        [
          ..._enabledList(stored, enabledKey, _strings(stored[enabledKey]),
              orderKey: orderKey),
          ?extra,
        ],
      ),
    ];
  }

  /// Only offered when the type supports more images than Primary.
  Widget? _imageOptionsButton(
      Map<String, dynamic> availType, AppLocalizations l10n) {
    final supported = _strings(availType['SupportedImageTypes']);
    if (supported.isEmpty ||
        (supported.length == 1 && supported.first == 'Primary')) {
      return null;
    }
    final type = availType['Type'].toString();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        icon: const Icon(Icons.tune),
        label: Text(l10n.adminLibFetcherSettings),
        onPressed: () async {
          final stored = _typeStored(type);
          if (stored == null) return;
          final options = await showImageOptionsDialog(
            context,
            type: type,
            supported: supported,
            stored: libraryProviders(stored['ImageOptions']),
            defaults: libraryProviders(availType['DefaultImageOptions']),
          );
          if (options != null && mounted) {
            _edit(() => stored['ImageOptions'] = options);
          }
        },
      ),
    );
  }

  List<Widget> _globalSection(String availKey, String disabledKey,
      String orderKey, String title, IconData icon) {
    if (libraryProviders(_available[availKey]).isEmpty) return const [];
    final disabled = _strings(_options[disabledKey]).toSet();
    final order = _strings(_options[orderKey]);
    return [
      _providerSection(title, icon, [
        for (var i = 0; i < order.length; i++)
          _providerRow(
            order[i],
            enabled: !disabled.contains(order[i]),
            onToggle: (on) => _edit(() {
              _options[disabledKey] = [
                ...disabled.where((n) => n != order[i]),
                if (!on) order[i],
              ];
            }),
            onMove: (delta) => _move(_options, orderKey, i, delta),
            index: i,
            count: order.length,
          ),
      ]),
    ];
  }

  /// Rows that tick names into [owner]'s [enabledKey], in [orderKey] order
  /// when there is one, else in [names] order.
  List<Widget> _enabledList(
    Map<String, dynamic> owner,
    String enabledKey,
    List<String> enabled, {
    String? orderKey,
    List<String>? names,
  }) {
    final order = orderKey == null ? names! : _strings(owner[orderKey]);
    return [
      for (var i = 0; i < order.length; i++)
        _providerRow(
          order[i],
          enabled: enabled.contains(order[i]),
          onToggle: (on) => _edit(() {
            owner[enabledKey] = [
              ...enabled.where((n) => n != order[i]),
              if (on) order[i],
            ];
          }),
          onMove: orderKey == null
              ? null
              : (delta) => _move(owner, orderKey, i, delta),
          index: i,
          count: order.length,
        ),
    ];
  }

  List<Widget> _orderList(Map<String, dynamic> owner, String orderKey) {
    final order = _strings(owner[orderKey]);
    return [
      for (var i = 0; i < order.length; i++)
        _providerRow(
          order[i],
          onMove: (delta) => _move(owner, orderKey, i, delta),
          index: i,
          count: order.length,
        ),
    ];
  }

  void _move(Map<String, dynamic> owner, String orderKey, int index, int delta) {
    final list = _strings(owner[orderKey]);
    final target = index + delta;
    if (target < 0 || target >= list.length) return;
    _edit(() {
      list.insert(target, list.removeAt(index));
      owner[orderKey] = list;
    });
  }

  Widget _providerRow(
    String name, {
    bool? enabled,
    ValueChanged<bool>? onToggle,
    ValueChanged<int>? onMove,
    required int index,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          if (enabled != null)
            Checkbox(
              value: enabled,
              onChanged: (v) => onToggle!(v ?? false),
            )
          else
            const SizedBox(width: 12),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 15))),
          if (onMove != null) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              visualDensity: VisualDensity.compact,
              onPressed: index > 0 ? () => onMove(-1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              visualDensity: VisualDensity.compact,
              onPressed: index < count - 1 ? () => onMove(1) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptions() {
    final l10n = AppLocalizations.of(context);
    final type = _type;
    final embeddedTitles = _options['EnableEmbeddedTitles'] as bool? ?? false;
    final hasSubtitleFetchers =
        libraryProviders(_available['SubtitleFetchers']).isNotEmpty;
    final embedded = [
      if (_hasEmbeddedTitles) ...[
        _optionSwitch('EnableEmbeddedTitles', l10n.adminLibEmbeddedTitles),
        if (embeddedTitles && !_emby)
          _optionSwitch(
              'EnableEmbeddedExtrasTitles', l10n.adminLibEmbeddedExtrasTitles),
      ],
      if (type == 'tvshows' && !_emby)
        _optionSwitch(
            'EnableEmbeddedEpisodeInfos', l10n.adminLibEmbeddedEpisodeInfos),
      if (_hasSubtitleOptions && !_emby) _buildEmbeddedSubtitles(l10n),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        adminSection(
          context,
          title: l10n.adminLibrarySectionGeneral,
          icon: Icons.tune,
          children: [
            if (!_emby)
              _optionSwitch('Enabled', l10n.adminLibEnableLibrary,
                  subtitle: l10n.adminLibEnableLibraryHelp, fallback: true),
            if (type == 'homevideos' || type == 'photos')
              _optionSwitch('EnablePhotos', l10n.adminLibEnablePhotos),
            _optionSwitch('EnableRealtimeMonitor', l10n.adminLibRealtimeMonitor,
                subtitle: l10n.adminLibRealtimeMonitorHint),
            if (_anyTypeOffers('ImageFetchers'))
              _optionSwitch(
                  'SaveLocalMetadata', l10n.adminLibSaveLocalMetadata),
            if (_has('ImportPlaylists'))
              _optionSwitch('ImportPlaylists', l10n.adminLibImportPlaylists),
            if (_has('ExcludeFromSearch'))
              _optionSwitch('ExcludeFromSearch', l10n.adminLibExcludeFromSearch),
          ],
        ),
        adminSection(
          context,
          title: l10n.adminLibrarySectionMetadata,
          icon: Icons.language,
          children: [
            _buildMetadataLanguage(l10n),
            _buildMetadataCountry(l10n),
            _buildRefreshInterval(l10n),
            if (type == 'tvshows') _buildSeasonZeroName(l10n),
          ],
        ),
        if (embedded.isNotEmpty)
          adminSection(
            context,
            title: l10n.adminLibrarySectionEmbedded,
            icon: Icons.data_object,
            children: embedded,
          ),
        if (_hasSubtitleOptions)
          adminSection(
            context,
            title: l10n.adminLibrarySectionSubtitles,
            icon: Icons.subtitles_outlined,
            children: [
              // These only matter with a subtitle downloader installed.
              if (hasSubtitleFetchers) ...[
                if (_cultures.isNotEmpty) _buildSubtitleLanguages(l10n),
                _optionSwitch('RequirePerfectSubtitleMatch',
                    l10n.adminLibRequirePerfectMatch),
                _optionSwitch('SkipSubtitlesIfAudioTrackMatches',
                    l10n.adminLibSkipIfAudioMatches),
                _optionSwitch('SkipSubtitlesIfEmbeddedSubtitlesPresent',
                    l10n.adminLibSkipIfEmbeddedSubs),
                if (_has('ForcedSubtitlesOnly'))
                  _optionSwitch('ForcedSubtitlesOnly',
                      l10n.adminLibForcedSubtitlesOnly),
              ],
              _optionSwitch('SaveSubtitlesWithMedia',
                  l10n.adminLibSaveSubtitlesWithMedia),
            ],
          ),
        if (_hasChapterOptions)
          adminSection(
            context,
            title: l10n.adminLibrarySectionImages,
            icon: Icons.image_outlined,
            children: [
              for (final (key, label) in [
                ('EnableTrickplayImageExtraction',
                    l10n.adminLibTrickplayExtraction),
                ('ExtractTrickplayImagesDuringLibraryScan',
                    l10n.adminLibTrickplayDuringScan),
                ('SaveTrickplayWithMedia', l10n.adminLibSaveTrickplayWithMedia),
              ])
                if (_has(key)) _optionSwitch(key, label),
              _optionSwitch('EnableChapterImageExtraction',
                  l10n.adminLibChapterImageExtraction),
              _optionSwitch('ExtractChapterImagesDuringLibraryScan',
                  l10n.adminLibChapterImagesDuringScan),
              if (_has('ThumbnailImagesIntervalSeconds'))
                _buildThumbnailInterval(l10n),
              if (_has('SaveLocalThumbnailSets'))
                _optionSwitch('SaveLocalThumbnailSets',
                    l10n.adminLibSaveThumbnailsWithMedia),
            ],
          ),
        if (_has('EnableMarkerDetection') &&
            (type == null || type == 'tvshows'))
          adminSection(
            context,
            title: l10n.adminLibrarySectionMarkers,
            icon: Icons.skip_next_outlined,
            children: [
              _optionSwitch('EnableMarkerDetection', l10n.adminLibIntroDetection),
              _optionSwitch('EnableMarkerDetectionDuringLibraryScan',
                  l10n.adminLibIntroDetectionDuringScan),
            ],
          ),
        if (_has('MinResumePct') && _hasResumeOptions)
          adminSection(
            context,
            title: l10n.adminDrawerResume,
            icon: Icons.play_circle_outline,
            children: [
              _intOption('MinResumePct', l10n.adminResumeMinPct,
                  l10n.adminResumeMinPctSubtitle),
              _intOption('MaxResumePct', l10n.adminResumeMaxPct,
                  l10n.adminResumeMaxPctSubtitle),
              _intOption('MinResumeDurationSeconds', l10n.adminResumeMinDuration,
                  l10n.adminResumeMinDurationSubtitle),
            ],
          ),
        if (type == 'tvshows')
          adminSection(
            context,
            title: l10n.adminLibrarySectionSeries,
            icon: Icons.live_tv,
            children: [
              _optionSwitch('EnableAutomaticSeriesGrouping',
                  l10n.adminLibAutomaticSeriesGrouping),
            ],
          ),
        if (type == 'music')
          adminSection(
            context,
            title: l10n.adminLibrarySectionMusic,
            icon: Icons.music_note,
            children: [
              if (_has('EnableLUFSScan'))
                _optionSwitch('EnableLUFSScan', l10n.adminLibLufsScan),
              _optionSwitch(
                  'SaveLyricsWithMedia', l10n.adminLibSaveLyricsWithMedia),
              if (!_emby) ...[
                _optionSwitch('PreferNonstandardArtistsTag',
                    l10n.adminLibPreferNonstandardArtist),
                _optionSwitch(
                    'UseCustomTagDelimiters', l10n.adminLibUseCustomTagDelimiters),
                adminFieldRow(
                  label: l10n.adminLibCustomTagDelimiters,
                  helper: l10n.adminLibCustomTagDelimitersHelp,
                  child: TextFormField(
                    initialValue:
                        _strings(_options['CustomTagDelimiters']).join(),
                    decoration: adminInputDecoration(),
                    // One delimiter per character.
                    onChanged: (v) {
                      _options['CustomTagDelimiters'] = v.split('');
                      widget.onChanged();
                    },
                  ),
                ),
                adminFieldRow(
                  label: l10n.adminLibDelimiterWhitelist,
                  helper: l10n.adminLibDelimiterWhitelistHelp,
                  child: TextFormField(
                    initialValue:
                        _strings(_options['DelimiterWhitelist']).join('\n'),
                    decoration: adminInputDecoration(),
                    minLines: 2,
                    maxLines: 6,
                    onChanged: (v) {
                      _options['DelimiterWhitelist'] = v
                          .split('\n')
                          .where((line) => line.trim().isNotEmpty)
                          .toList();
                      widget.onChanged();
                    },
                  ),
                ),
              ],
            ],
          ),
        if (type == 'movies' || type == 'mixed')
          adminSection(
            context,
            title: l10n.adminLibrarySectionMovies,
            icon: Icons.movie_outlined,
            children: [
              if (_emby)
                _optionSwitch('ImportCollections', l10n.adminLibImportCollections)
              else
                _optionSwitch('AutomaticallyAddToCollection',
                    l10n.adminLibAutoAddToCollection),
            ],
          ),
      ],
    );
  }

  Widget _optionSwitch(String key, String title,
      {String? subtitle, bool fallback = false}) {
    return adminSwitchRow(
      title: title,
      subtitle: subtitle,
      value: _options[key] as bool? ?? fallback,
      onChanged: (v) => _set(key, v),
    );
  }

  /// The server needs a number, so a blank or bad entry keeps the stored one.
  Widget _intOption(String key, String label, String helper) {
    return adminFieldRow(
      label: label,
      helper: helper,
      child: TextFormField(
        initialValue: '${_options[key] ?? ''}',
        decoration: adminInputDecoration(),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final value = int.tryParse(v.trim());
          if (value == null) return;
          _options[key] = value;
          widget.onChanged();
        },
      ),
    );
  }

  /// Emby takes seconds between thumbnails, or -1 for one per chapter.
  Widget _buildThumbnailInterval(AppLocalizations l10n) {
    final current =
        (_options['ThumbnailImagesIntervalSeconds'] as num?)?.toInt() ?? -1;
    return adminFieldRow(
      label: l10n.adminLibThumbnailInterval,
      child: DropdownButtonFormField<int>(
        initialValue: current,
        isExpanded: true,
        decoration: adminInputDecoration(),
        items: [
          for (final s in {10, -1, current})
            DropdownMenuItem(
              value: s,
              child: Text(s < 0
                  ? l10n.adminLibThumbnailAtChapters
                  : l10n.adminLibThumbnailEverySeconds(s)),
            ),
        ],
        onChanged: (v) => _set('ThumbnailImagesIntervalSeconds', v ?? -1),
      ),
    );
  }

  Widget _buildRefreshInterval(AppLocalizations l10n) {
    final current =
        (_options['AutomaticRefreshIntervalDays'] as num?)?.toInt() ?? 0;
    // A stored value outside the presets stays listed so a save never
    // changes it.
    final days = [0, 30, 60, 90, if (![0, 30, 60, 90].contains(current)) current];
    return adminFieldRow(
      label: l10n.adminLibRefreshInterval,
      child: DropdownButtonFormField<int>(
        initialValue: current,
        isExpanded: true,
        decoration: adminInputDecoration(),
        items: days
            .map((d) => DropdownMenuItem(
                  value: d,
                  child: Text(d == 0
                      ? l10n.adminLibRefreshNever
                      : l10n.adminLibRefreshDays(d)),
                ))
            .toList(),
        onChanged: (v) => _set('AutomaticRefreshIntervalDays', v ?? 0),
      ),
    );
  }

  Widget _buildEmbeddedSubtitles(AppLocalizations l10n) {
    final current =
        _options['AllowEmbeddedSubtitles']?.toString() ?? 'AllowAll';
    final options = <(String, String)>[
      ('AllowAll', l10n.adminLibEmbeddedAllowAll),
      ('AllowText', l10n.adminLibEmbeddedAllowText),
      ('AllowImage', l10n.adminLibEmbeddedAllowImage),
      ('AllowNone', l10n.adminLibEmbeddedAllowNone),
    ];
    return adminFieldRow(
      label: l10n.adminLibAllowEmbeddedSubtitles,
      child: DropdownButtonFormField<String>(
        initialValue:
            options.any((o) => o.$1 == current) ? current : 'AllowAll',
        isExpanded: true,
        decoration: adminInputDecoration(),
        items: options
            .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
            .toList(),
        onChanged: (v) => _set('AllowEmbeddedSubtitles', v),
      ),
    );
  }

  /// Stored as lower-case three-letter codes.
  Widget _buildSubtitleLanguages(AppLocalizations l10n) {
    final selected = _strings(_options['SubtitleDownloadLanguages']);
    final seen = <String>{};
    final languages = [
      for (final c in _cultures)
        if (c['ThreeLetterISOLanguageName'] != null &&
            seen.add(c['ThreeLetterISOLanguageName'].toString().toLowerCase()))
          (
            c['ThreeLetterISOLanguageName'].toString().toLowerCase(),
            (c['DisplayName'] ?? c['Name']).toString(),
          ),
    ];
    return adminFieldRow(
      label: l10n.adminLibDownloadLanguages,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (code, name) in languages)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected.contains(code),
                title: Text(name),
                onChanged: (on) => _set('SubtitleDownloadLanguages', [
                  ...selected.where((c) => c != code),
                  if (on == true) code,
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeasonZeroName(AppLocalizations l10n) {
    return adminFieldRow(
      label: l10n.adminLibSeasonZeroName,
      child: TextFormField(
        initialValue: _options['SeasonZeroDisplayName'] as String? ?? '',
        decoration: adminInputDecoration(),
        onChanged: (v) {
          _options['SeasonZeroDisplayName'] = v;
          widget.onChanged();
        },
      ),
    );
  }

  Widget _buildMetadataLanguage(AppLocalizations l10n) {
    return adminCodeDropdown(
      label: l10n.adminPreferredMetadataLanguage,
      helper: _cultures.isEmpty ? l10n.adminMetadataLanguageHint : null,
      defaultLabel: l10n.adminLibDefault,
      current: _options['PreferredMetadataLanguage'] as String? ?? '',
      rawItems: _cultures.map((c) => (
            (c['TwoLetterISOLanguageName'] ?? c['ThreeLetterISOLanguageName'])
                ?.toString(),
            (c['DisplayName'] ?? c['Name'])?.toString(),
          )),
      onChanged: (v) => _set('PreferredMetadataLanguage', v),
    );
  }

  Widget _buildMetadataCountry(AppLocalizations l10n) {
    return adminCodeDropdown(
      label: l10n.adminMetadataCountryCode,
      helper: _countries.isEmpty ? l10n.adminMetadataCountryHint : null,
      defaultLabel: l10n.adminLibDefault,
      current: _options['MetadataCountryCode'] as String? ?? '',
      rawItems: _countries.map((c) => (
            (c['TwoLetterISORegionName'] ?? c['Name'])?.toString(),
            (c['DisplayName'] ?? c['Name'])?.toString(),
          )),
      onChanged: (v) => _set('MetadataCountryCode', v),
    );
  }
}
