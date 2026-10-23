import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../l10n/current_app_localizations.dart';
import '../../preference/preference_constants.dart';
import '../models/aggregated_item.dart';
import '../models/home_row.dart';
import '../services/row_data_source.dart';

/// Which formats the library tab is currently showing. Only meaningful for
/// mixed libraries; single-format libraries always behave like [all].
enum BookScope { all, books, audiobooks, comics }

/// What the main area of the book library lists. The browse entries list the
/// whole library, and only [titles] follows the format filter.
enum BookPane { titles, series, authors, genres, collections, favorites }

typedef _PanePage = ({List<AggregatedItem> items, int read, bool hasMore});

class BookBrowseViewModel extends ChangeNotifier with BookLibraryHelpers {
  final RowDataSource _dataSource;
  final MediaServerClient _client;
  final String libraryId;

  // shortcut: titles past the first 5000 are left out of the counts, series
  // and authors, page the query if a library that large shows up.
  static const _titleScanLimit = 5000;

  /// The sorts the title grid offers, in menu order.
  static const titleSorts = [
    LibrarySortBy.dateAdded,
    LibrarySortBy.name,
    LibrarySortBy.premiereDate,
    LibrarySortBy.datePlayed,
    LibrarySortBy.random,
  ];

  static const _panePageSize = 60;
  static const _previewSize = 6;
  // Each collection costs a request to check that it holds books.
  static const _collectionPageSize = 20;
  static const _paneFields =
      'DateCreated,Type,UserData,RunTimeTicks,ProductionYear,SeriesName,'
      'ParentId,Path,People,AlbumArtist,Artists,ChildCount,ImageTags,'
      'SeriesId,SeriesPrimaryImageTag,PrimaryImageAspectRatio';

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String _libraryName = '';
  String get libraryName => _libraryName;

  String? _collectionType;
  String? get collectionType => _collectionType;

  @override
  bool get isAudiobookLibrary => _collectionType == 'audiobooks';

  BookScope _scope = BookScope.all;
  @override
  BookScope get scope => _scope;

  int _bookCount = 0;
  @override
  int get bookCount => _bookCount;
  int _audiobookCount = 0;
  @override
  int get audiobookCount => _audiobookCount;
  int _comicCount = 0;
  @override
  int get comicCount => _comicCount;

  int _titleCount = 0;
  int get titleCount => _titleCount;
  int _genreCount = 0;
  int get genreCount => _genreCount;
  List<AggregatedItem> _genrePreview = const [];
  List<AggregatedItem> get genrePreview => _genrePreview;

  // The browse entries list the whole library whatever the format filter
  // says, and so do their counts.
  List<AggregatedItem> _allSeries = const [];
  List<AggregatedItem> get allSeries => _allSeries;
  int get seriesCount => _allSeries.length;
  int _authorCount = 0;
  int get authorCount => _authorCount;
  List<AggregatedItem> _artists = const [];
  Map<String, int> _authorTitles = const {};

  List<AggregatedItem> get authorPreview =>
      [..._artists, ..._extraAuthors].take(_previewSize).toList();

  int authorTitleCount(AggregatedItem author) =>
      _authorTitles[author.name.toLowerCase()] ?? 0;

  int get favoriteCount {
    final row = _favoritesRow;
    if (row == null) return 0;
    return row.totalCount > 0 ? row.totalCount : row.items.length;
  }

  int get collectionCount => _collectionsRow?.items.length ?? 0;

  /// Only the first collections get checked for books at load, so the count
  /// is a floor while more are left unchecked.
  bool get collectionCountIsFloor =>
      (_collectionsRow?.totalCount ?? 0) > _collectionsChecked;
  int _collectionsChecked = 0;

  int titleCountFor(BookScope scope) => switch (scope) {
    BookScope.all => _titleCount,
    BookScope.books => _bookCount,
    BookScope.audiobooks => _audiobookCount,
    BookScope.comics => _comicCount,
  };

  HomeRow? get resumeRow => _resumeRow;

  BookPane _pane = BookPane.titles;
  BookPane get pane => _pane;

  LibrarySortBy _titleSort;
  LibrarySortBy get titleSort => _titleSort;

  List<AggregatedItem> _paneItems = const [];
  List<AggregatedItem> get paneItems => _paneItems;
  final Set<String> _paneIds = {};
  bool _paneLoading = false;
  bool get paneLoading => _paneLoading;
  bool _paneHasMore = false;
  bool get paneHasMore => _paneHasMore;

  // Server rows read so far, which is where the next page starts. It runs
  // ahead of what's shown when a pane drops rows, like comics in the books
  // scope.
  int _paneFetched = 0;
  int _paneGeneration = 0;
  bool _paneUntyped = false;
  List<AggregatedItem> _extraAuthors = const [];
  bool _disposed = false;

  HomeRow? _resumeRow;
  HomeRow? _collectionsRow;
  HomeRow? _favoritesRow;

  String get _serverId => _client.baseUrl;
  @override
  ImageApi get imageApi => _dataSource.imageApi;

  BookBrowseViewModel({
    required this.libraryId,
    required RowDataSource dataSource,
    required MediaServerClient client,
    String? collectionType,
    LibrarySortBy titleSort = LibrarySortBy.dateAdded,
  }) : _dataSource = dataSource, // ignore: prefer_initializing_formals
       _client = client, // ignore: prefer_initializing_formals
       _collectionType = collectionType, // ignore: prefer_initializing_formals
       _titleSort = titleSort; // ignore: prefer_initializing_formals

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    final l10n = currentAppLocalizations();

    try {
      final itemData = await _client.itemsApi.getItem(libraryId);
      _libraryName = itemData['Name'] as String? ?? l10n.books;
      final fetchedType = (itemData['CollectionType'] as String?)?.toLowerCase();
      if (fetchedType != null && fetchedType.isNotEmpty) {
        _collectionType = fetchedType;
      }
    } catch (_) {}

    // The grid asks for the library's types, so it starts once they're known.
    unawaited(reloadPane());

    try {
      final resumeF = _dataSource.loadBookResume(
        libraryId,
        _serverId,
        includeItemTypes: combinedTypes,
        title: isAudiobookLibrary
            ? l10n.continueListening
            : l10n.continueReading,
      );
      final artistsF = _dataSource.loadBookAuthors(libraryId, _serverId);
      final favoritesF = _dataSource.loadLibraryFavorites(
        libraryId,
        _serverId,
        includeItemTypes: combinedTypes,
      );
      final collectionsF = _loadBookCollections();
      final genresF = _loadGenres();
      final titlesF = _loadTitles();
      final foldersF = _loadFolders();

      await Future.wait([
        resumeF,
        artistsF,
        favoritesF,
        collectionsF,
        genresF,
        titlesF,
        foldersF,
      ]);

      _resumeRow = await resumeF;
      _favoritesRow = await favoritesF;
      _collectionsRow = await collectionsF;
      final genres = await genresF;
      _genrePreview = genres.items;
      _genreCount = genres.total;

      final titles = await titlesF;
      _titleCount = titles.length;
      _bookCount = titles.where(isBookItem).length;
      _audiobookCount = titles.where(isAudiobookItem).length;
      _comicCount = titles.where(isComicItem).length;
      _allSeries = bookSeriesEntries(books: titles, folders: await foldersF);

      _authorTitles = _tallyAuthorTitles(titles);
      final artists = await artistsF;
      _artists = artists.items;
      _extraAuthors = _peopleAuthors(
        titles,
        known: {for (final artist in artists.items) artist.name.toLowerCase()},
      );
      _authorCount =
          (artists.totalCount > 0 ? artists.totalCount : artists.items.length) +
          _extraAuthors.length;

      // A refresh can drop the format the user was on, and leaving the scope
      // there strands them on a tab the filter no longer offers.
      if (_scope != BookScope.all &&
          (!isMixedLibrary || !availableScopes.contains(_scope))) {
        _scope = BookScope.all;
        if (_pane == BookPane.titles) unawaited(reloadPane());
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  void setScope(BookScope value) {
    if (_scope == value) return;
    _scope = value;
    notifyListeners();
    if (_pane == BookPane.titles) unawaited(reloadPane());
  }

  void setPane(BookPane value) {
    if (_pane == value) return;
    _pane = value;
    unawaited(reloadPane());
  }

  void setTitleSort(LibrarySortBy value) {
    if (_titleSort == value) return;
    _titleSort = value;
    if (_pane == BookPane.titles || _pane == BookPane.favorites) {
      unawaited(reloadPane());
    } else {
      notifyListeners();
    }
  }

  Future<void> reloadPane() {
    _paneGeneration++;
    _paneItems = const [];
    _paneIds.clear();
    _paneFetched = 0;
    _paneHasMore = true;
    _paneUntyped = false;
    // A page still loading belongs to the old list and won't clear this.
    _paneLoading = false;
    return loadMorePane();
  }

  Future<void> loadMorePane() async {
    if (_paneLoading || !_paneHasMore || _disposed) return;
    final generation = _paneGeneration;
    _paneLoading = true;
    notifyListeners();
    final added = <AggregatedItem>[];
    try {
      // A page can hold nothing this pane keeps, like a page of comics in the
      // books scope, so keep reading until one adds something or the source
      // runs out.
      while (added.isEmpty && _paneHasMore) {
        final page = await _fetchPanePage(_paneFetched);
        if (_disposed || generation != _paneGeneration) return;
        _paneFetched += page.read;
        _paneHasMore = page.hasMore && page.read > 0;
        for (final item in page.items) {
          // A random sort reshuffles on every request, so its pages overlap.
          if (_paneIds.add(item.id)) added.add(item);
        }
      }
    } catch (_) {
      if (generation == _paneGeneration) _paneHasMore = false;
    }
    if (_disposed || generation != _paneGeneration) return;
    _paneItems = [..._paneItems, ...added];
    _paneLoading = false;
    notifyListeners();
  }

  Future<_PanePage> _fetchPanePage(int start) async {
    switch (_pane) {
      case BookPane.titles:
        return _titlesPage(start, favorites: false);
      case BookPane.favorites:
        return _titlesPage(start, favorites: true);
      case BookPane.series:
        return (items: _allSeries, read: _allSeries.length, hasMore: false);
      case BookPane.authors:
        final page = _pageOf(
          await _client.itemsApi.getArtists(
            parentId: libraryId,
            userId: _client.userId,
            sortBy: 'SortName',
            sortOrder: 'Ascending',
            startIndex: start,
            limit: _panePageSize,
            recursive: true,
            fields: 'PrimaryImageAspectRatio,SortName',
          ),
          start,
          _panePageSize,
        );
        if (page.hasMore) return page;
        // Ebook authors only exist as people on the titles, so they're listed
        // after the artists.
        final names = {
          for (final author in [..._paneItems, ...page.items])
            author.name.toLowerCase(),
        };
        return (
          items: [
            ...page.items,
            for (final author in _extraAuthors)
              if (names.add(author.name.toLowerCase())) author,
          ],
          read: page.read,
          hasMore: false,
        );
      case BookPane.genres:
        return _pageOf(
          await _client.itemsApi.getGenres(
            parentId: libraryId,
            sortBy: 'SortName',
            sortOrder: 'Ascending',
            startIndex: start,
            limit: _panePageSize,
            recursive: true,
            fields: 'ItemCounts,PrimaryImageAspectRatio',
            includeItemTypes: combinedTypes,
          ),
          start,
          _panePageSize,
        );
      case BookPane.collections:
        final page = _pageOf(
          await _client.itemsApi.getItems(
            parentId: libraryId,
            includeItemTypes: const ['BoxSet'],
            recursive: true,
            sortBy: 'SortName',
            sortOrder: 'Ascending',
            startIndex: start,
            limit: _collectionPageSize,
            fields: _paneFields,
            enableImageTypes: 'Primary',
            imageTypeLimit: 1,
          ),
          start,
          _collectionPageSize,
        );
        return (
          items: await _holdingBooks(page.items),
          read: page.read,
          hasMore: page.hasMore,
        );
    }
  }

  Future<_PanePage> _titlesPage(int start, {required bool favorites}) async {
    final types = favorites ? combinedTypes : scopedTypes;
    final sort = _titleSort;
    final descending = sort == LibrarySortBy.dateAdded ||
        sort == LibrarySortBy.premiereDate ||
        sort == LibrarySortBy.datePlayed;
    Future<Map<String, dynamic>> fetch() => _client.itemsApi.getItems(
      parentId: libraryId,
      includeItemTypes: _paneUntyped ? null : types,
      excludeItemTypes: _paneUntyped
          ? const ['Folder', 'CollectionFolder', 'UserView']
          : null,
      recursive: true,
      isFavorite: favorites ? true : null,
      sortBy: sort.apiValue,
      sortOrder: descending ? 'Descending' : 'Ascending',
      startIndex: start,
      limit: _panePageSize,
      fields: _paneFields,
      enableImageTypes: 'Primary',
      imageTypeLimit: 1,
    );
    var resp = await fetch();
    // Some servers return nothing when the query names book types but answer
    // without them, so the rest of the pages go out untyped.
    if (start == 0 &&
        !_paneUntyped &&
        ((resp['Items'] as List?)?.isEmpty ?? true)) {
      _paneUntyped = true;
      resp = await fetch();
    }
    final page = _pageOf(
      resp,
      start,
      _panePageSize,
      keep: _paneUntyped ? (raw) => types.contains(raw['Type']) : null,
    );
    if (favorites) return page;
    return (
      items: page.items.where(matchesScope).toList(),
      read: page.read,
      hasMore: page.hasMore,
    );
  }

  _PanePage _pageOf(
    Map<String, dynamic> resp,
    int start,
    int pageSize, {
    bool Function(Map raw)? keep,
  }) {
    final raw = (resp['Items'] as List? ?? const []).whereType<Map>().toList();
    final total = resp['TotalRecordCount'] as int?;
    return (
      items: [
        for (final item in raw)
          if (item['Id'] != null && (keep == null || keep(item)))
            AggregatedItem(
              id: item['Id'].toString(),
              serverId: _serverId,
              rawData: item.cast<String, dynamic>(),
            ),
      ],
      read: raw.length,
      hasMore: total != null
          ? start + raw.length < total
          : raw.length >= pageSize,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Every title in the library, with the fields the counts, series and
  /// authors need.
  Future<List<AggregatedItem>> _loadTitles() async {
    final types = combinedTypes;
    Future<Map<String, dynamic>> fetch({required bool typed}) =>
        _client.itemsApi.getItems(
          parentId: libraryId,
          includeItemTypes: typed ? types : null,
          excludeItemTypes: typed
              ? null
              : const ['Folder', 'CollectionFolder', 'UserView'],
          recursive: true,
          limit: _titleScanLimit,
          sortBy: 'SortName',
          sortOrder: 'Ascending',
          fields: 'SeriesName,ParentId,Path,People,AlbumArtist,Artists',
          enableImageTypes: 'Primary',
          imageTypeLimit: 1,
          enableTotalRecordCount: false,
        );
    try {
      var rawItems = (await fetch(typed: true))['Items'] as List? ?? const [];
      if (rawItems.isEmpty) {
        rawItems = (await fetch(typed: false))['Items'] as List? ?? const [];
      }
      return [
        for (final raw in rawItems.whereType<Map>())
          if (raw['Id'] != null && types.contains(raw['Type']))
            AggregatedItem(
              id: raw['Id'].toString(),
              serverId: _serverId,
              rawData: raw.cast<String, dynamic>(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Authors who only appear as people on the [titles], which is all an ebook
  /// has, minus the [known] ones.
  List<AggregatedItem> _peopleAuthors(
    List<AggregatedItem> titles, {
    required Set<String> known,
  }) {
    final authors = <AggregatedItem>[];
    for (final title in titles) {
      final people = title.rawData['People'] as List? ?? const [];
      for (final person in people.whereType<Map>()) {
        if (person['Type'] != 'Author' && person['Role'] != 'Author') continue;
        final name = person['Name'] as String?;
        if (name == null || name.isEmpty || !known.add(name.toLowerCase())) {
          continue;
        }
        final id = person['Id'] as String? ?? name;
        final tag = person['PrimaryImageTag'] as String?;
        authors.add(
          AggregatedItem(
            id: id,
            serverId: _serverId,
            rawData: {
              'Id': id,
              'Name': name,
              'Type': 'Person',
              if (tag != null) 'ImageTags': {'Primary': tag},
            },
          ),
        );
      }
    }
    return authors
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The first genres with the library's types, and how many there are.
  Future<({List<AggregatedItem> items, int total})> _loadGenres() async {
    try {
      final resp = await _client.itemsApi.getGenres(
        parentId: libraryId,
        includeItemTypes: combinedTypes,
        recursive: true,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        limit: _previewSize,
        fields: 'ItemCounts',
      );
      final items = _pageOf(resp, 0, _previewSize).items;
      return (
        items: items,
        total: resp['TotalRecordCount'] as int? ?? items.length,
      );
    } catch (_) {
      return (items: const <AggregatedItem>[], total: 0);
    }
  }

  /// How many titles each author name is on, as people, album artist or
  /// artists.
  static Map<String, int> _tallyAuthorTitles(List<AggregatedItem> titles) {
    final counts = <String, int>{};
    for (final title in titles) {
      final raw = title.rawData;
      final people = raw['People'] as List? ?? const [];
      final artists = raw['Artists'] as List? ?? const [];
      final names = <String>{
        for (final person in people.whereType<Map>())
          if (person['Type'] == 'Author' || person['Role'] == 'Author')
            if (person['Name'] case final String name) name.toLowerCase(),
        if (raw['AlbumArtist'] case final String name) name.toLowerCase(),
        for (final artist in artists.whereType<String>()) artist.toLowerCase(),
      };
      for (final name in names) {
        counts.update(name, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  /// Up to three member covers of a series, for its stacked look.
  List<String> seriesCoverUrls(AggregatedItem series) {
    final covers = series.rawData['StackCovers'] as List? ?? const [];
    return [
      for (final cover in covers.whereType<Map>())
        imageApi.getPrimaryImageUrl(
          cover['Id'] as String,
          maxHeight: 400,
          tag: cover['Tag'] as String?,
        ),
    ];
  }

  Future<List<AggregatedItem>> _loadFolders() async {
    try {
      final resp = await _client.itemsApi.getItems(
        parentId: libraryId,
        includeItemTypes: const ['Folder'],
        recursive: true,
        fields: 'ParentId',
        enableImageTypes: 'Primary',
        imageTypeLimit: 1,
        enableTotalRecordCount: false,
      );
      return [
        for (final raw in (resp['Items'] as List? ?? const []).whereType<Map>())
          if (raw['Id'] != null)
            AggregatedItem(
              id: raw['Id'].toString(),
              serverId: _serverId,
              rawData: raw.cast<String, dynamic>(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<HomeRow> _loadBookCollections() async {
    final raw = await _dataSource.loadLibraryCollections(libraryId, _serverId);
    _collectionsChecked = raw.items.length;
    if (raw.items.isEmpty) return raw;
    return raw.copyWith(items: await _holdingBooks(raw.items));
  }

  /// The [boxes] holding something this library shows.
  Future<List<AggregatedItem>> _holdingBooks(List<AggregatedItem> boxes) async {
    final types = combinedTypes;
    final containsBooks = await Future.wait(
      boxes.map((box) async {
        try {
          final resp = await _client.itemsApi.getItems(
            parentId: box.id,
            includeItemTypes: types,
            recursive: true,
            limit: 8,
          );
          final items = (resp['Items'] as List?) ?? const [];
          return items.any((it) {
            final type = (it is Map ? it['Type'] : null) as String?;
            return type != null && types.contains(type);
          });
        } catch (_) {
          return false;
        }
      }),
    );
    return [
      for (var i = 0; i < boxes.length; i++)
        if (containsBooks[i]) boxes[i],
    ];
  }
}

/// What both book library view models know about a library's formats and
/// titles.
mixin BookLibraryHelpers {
  ImageApi get imageApi;
  bool get isAudiobookLibrary;
  BookScope get scope;
  int get bookCount;
  int get audiobookCount;
  int get comicCount;

  /// True when the library holds 2 or more formats (books, audiobooks, comics),
  /// which turns on the format filter.
  bool get isMixedLibrary {
    if (isAudiobookLibrary) return false;
    var count = 0;
    if (bookCount > 0) count++;
    if (audiobookCount > 0) count++;
    if (comicCount > 0) count++;
    return count >= 2;
  }

  /// The formats this library holds, after All.
  List<BookScope> get availableScopes => [
    BookScope.all,
    if (bookCount > 0) BookScope.books,
    if (audiobookCount > 0) BookScope.audiobooks,
    if (comicCount > 0) BookScope.comics,
  ];

  List<String> get audiobookTypes =>
      isAudiobookLibrary ? const ['AudioBook', 'Audio'] : const ['AudioBook'];

  /// Types for whole-library queries. A books library asks for AudioBook too,
  /// so audiobooks filed in it show up. Jellyfin types comics as Book, so
  /// they're told apart here instead.
  List<String> get combinedTypes =>
      isAudiobookLibrary
          ? const ['AudioBook', 'Audio']
          : const ['Book', 'AudioBook'];

  /// Types matching the active format.
  List<String> get scopedTypes {
    if (isAudiobookLibrary) return audiobookTypes;
    return switch (scope) {
      BookScope.books => const ['Book'],
      BookScope.audiobooks => audiobookTypes,
      BookScope.comics => const ['Book'],
      BookScope.all => combinedTypes,
    };
  }

  /// Whether [item] is an audiobook rather than a book or comic. The server's
  /// type wins, and the guess only settles bare audio items.
  bool isAudiobookItem(AggregatedItem item) {
    if (item.isComic) return false;
    final type = item.type;
    if (type == 'AudioBook' || type == 'Audio') return true;
    if (type == 'Book') return false;
    return item.isAudiobook;
  }

  bool isComicItem(AggregatedItem item) => item.isComic;

  bool isBookItem(AggregatedItem item) => !isAudiobookItem(item) && !item.isComic;

  bool matchesScope(AggregatedItem item) => switch (scope) {
    BookScope.all => true,
    BookScope.books => isBookItem(item),
    BookScope.audiobooks => isAudiobookItem(item),
    BookScope.comics => isComicItem(item),
  };

  /// Time left in an audiobook, or in a book with server progress. Null
  /// without a runtime.
  Duration? remainingFor(AggregatedItem item) {
    final runtime = item.runtime;
    if (runtime == null) return null;
    final pct = item.playedPercentage;
    if (pct == null || pct <= 0) return runtime;
    if (pct >= 100) return Duration.zero;
    return Duration(
      microseconds: (runtime.inMicroseconds * (1.0 - pct / 100.0)).round(),
    );
  }

  String bookSubtitle(AggregatedItem item) {
    final l10n = currentAppLocalizations();
    switch (item.type) {
      case 'BoxSet':
        final count = item.childCount;
        return count != null && count > 0 ? '$count items' : '';
      case 'BookSeries':
        final count = item.childCount ?? 0;
        return count > 0 ? l10n.bookSeriesItemCount(count) : '';
      case 'MusicArtist':
        return '';
      default:
        final people = item.rawData['People'] as List?;
        final authorPerson = people?.whereType<Map>().firstWhereOrNull(
              (p) => p['Type'] == 'Author' || p['Role'] == 'Author',
            );
        final authorFromPeople = authorPerson?['Name'] as String?;

        final author =
            authorFromPeople ??
            (item.rawData['AlbumArtist'] as String?) ??
            item.seriesName ??
            (item.rawData['Artists'] as List?)?.cast<String>().firstOrNull ??
            '';
        return author;
    }
  }

  String? bookImageUrl(AggregatedItem item) {
    if (item.primaryImageTag != null) {
      return imageApi.getPrimaryImageUrl(
        item.id,
        maxHeight: 400,
        tag: item.primaryImageTag,
      );
    }
    final fieldTag = item.primaryImageTagField;
    final fieldItemId = item.primaryImageItemId;
    if (fieldTag != null && fieldItemId != null) {
      return imageApi.getPrimaryImageUrl(
        fieldItemId,
        maxHeight: 400,
        tag: fieldTag,
      );
    }
    final albumTag = item.albumPrimaryImageTag;
    final albumId = item.albumId;
    if (albumTag != null && albumId != null) {
      return imageApi.getPrimaryImageUrl(
        albumId,
        maxHeight: 400,
        tag: albumTag,
      );
    }
    final parentTag =
        (item.rawData['SeriesPrimaryImageTag'] as String?) ??
        (item.rawData['ParentPrimaryImageTag'] as String?);
    final parentId =
        item.rawData['SeriesId']?.toString() ??
        item.rawData['ParentPrimaryImageItemId']?.toString() ??
        item.parentId;
    if (parentTag != null && parentId != null) {
      return imageApi.getPrimaryImageUrl(parentId, maxHeight: 400, tag: parentTag);
    }
    return null;
  }
}

/// The series in a book library, one `BookSeries` entry each.
///
/// A folder two or more comics sit in directly is a series, unless it's one of
/// the library's roots, the only folders whose parent isn't another folder of
/// the library. Ebooks don't count toward it, since they're filed in author
/// folders, and neither do audiobooks split into chapter files. Books sharing
/// a SeriesName are a series too, unless every one of them already sits in a
/// series folder.
List<AggregatedItem> bookSeriesEntries({
  required List<AggregatedItem> books,
  required List<AggregatedItem> folders,
}) {
  final folderIds = {for (final folder in folders) folder.id};
  final seriesFolders = {
    for (final folder in folders)
      if (folderIds.contains(folder.parentId)) folder.id: folder,
  };
  final byFolder = <String, List<AggregatedItem>>{};
  final byName = <String, List<AggregatedItem>>{};
  for (final book in books) {
    final parent = book.parentId;
    if (book.isComic && seriesFolders.containsKey(parent)) {
      byFolder.putIfAbsent(parent!, () => []).add(book);
    }
    final name = book.seriesName?.trim();
    if (name != null && name.isNotEmpty) {
      byName.putIfAbsent(name, () => []).add(book);
    }
  }
  byFolder.removeWhere((_, members) => members.length < 2);

  return [
    for (final MapEntry(key: id, value: members) in byFolder.entries)
      _seriesEntry(id, seriesFolders[id]!.name, members, seriesFolders[id]),
    for (final MapEntry(key: name, value: members) in byName.entries)
      if (members.length >= 2 &&
          !members.every((m) => byFolder.containsKey(m.parentId)))
        _seriesEntry('bookSeries:$name', name, members, null),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

AggregatedItem _seriesEntry(
  String id,
  String name,
  List<AggregatedItem> members,
  AggregatedItem? folder,
) {
  final folderTag = folder?.primaryImageTag;
  final cover = members.firstWhere(
    (m) => m.primaryImageTag != null,
    orElse: () => members.first,
  );
  final stack = members.where((m) => m.primaryImageTag != null).take(3);
  return AggregatedItem(
    id: id,
    serverId: members.first.serverId,
    rawData: {
      'Name': name,
      'Type': 'BookSeries',
      'ChildCount': members.length,
      'StackCovers': [
        for (final member in stack)
          {'Id': member.id, 'Tag': member.primaryImageTag},
      ],
      if (folder != null) 'IsFolder': true,
      if (folderTag != null)
        'ImageTags': {'Primary': folderTag}
      else if (cover.primaryImageTag != null) ...{
        'PrimaryImageItemId': cover.id,
        'PrimaryImageTag': cover.primaryImageTag,
      },
    },
  );
}
