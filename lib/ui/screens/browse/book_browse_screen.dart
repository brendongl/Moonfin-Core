import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/viewmodels/book_browse_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/grid_focus_node_mixin.dart';
import '../../../util/focus/row_focus_coordinator.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/book/book_browse_nav.dart';
import '../../widgets/book/book_card.dart';
import '../../widgets/book/book_empty_state.dart';
import '../../widgets/book/book_format_badge.dart';
import '../../widgets/book/book_list_tile.dart';
import '../../widgets/book/book_navigation.dart';
import '../../widgets/book/book_scope_filter.dart';
import '../../widgets/book/book_shelf_row.dart';
import '../../widgets/book/discover/book_discover_tab.dart';
import '../../widgets/focus/can_claim_initial_focus.dart';
import '../../widgets/focus/context_menu_sheet.dart';
import '../../widgets/focus/focusable_wrapper.dart';
import '../../widgets/skeleton/skeleton_library_grid.dart';
import '../../widgets/sliding_pill_tabs.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/left_sidebar.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/top_toolbar.dart';
import '../detail/playlist_sort_filter_bar.dart' show librarySortLabel;

class BookBrowseScreen extends StatefulWidget {
  final String libraryId;
  final String? collectionType;

  const BookBrowseScreen({
    super.key,
    required this.libraryId,
    this.collectionType,
  });

  @override
  State<BookBrowseScreen> createState() => _BookBrowseScreenState();
}

class _BookBrowseScreenState extends State<BookBrowseScreen>
    with GridFocusNodeMixin {
  late final BookBrowseViewModel _vm;
  final _prefs = GetIt.instance<UserPreferences>();
  int _tab = 0;

  final _coordinator = RowFocusCoordinator();
  // Never attached. As the initial focus target it keeps RequestInitialFocus
  // from parking focus in the sidebar before the content loads, and
  // _onChanged lands focus on the content once it does.
  final _initialFocusNode = FocusNode(debugLabel: 'bookInitialContent');
  bool _landedOnContent = false;
  final _scopeFocusNode = FocusNode(debugLabel: 'bookScopeFilter');
  final _tabsFocusNode = FocusNode(debugLabel: 'bookTabs');
  final _toolbarFocusNode = FocusNode(debugLabel: 'bookToolbar');
  final _continueRowKey = GlobalKey<LockedFocusRowState>();
  final _continueContainerKey = GlobalKey();
  final _scopeContainerKey = GlobalKey();
  final _tabsContainerKey = GlobalKey();
  final _toolbarContainerKey = GlobalKey();
  final Map<String, FocusNode> _railNodes = {};
  final _scrollController = ScrollController();

  /// Where the grid sits in the vertical focus chain, for leaving its top row.
  int _gridEntryIndex = -1;

  EnumPreference<LibrarySortBy> get _sortPref =>
      UserPreferences.librarySortBy('books_${widget.libraryId}');

  @override
  void initState() {
    super.initState();
    final saved = _prefs.get(_sortPref);
    _vm = BookBrowseViewModel(
      libraryId: widget.libraryId,
      dataSource: GetIt.instance<RowDataSource>(),
      client: GetIt.instance<MediaServerClient>(),
      collectionType: widget.collectionType,
      titleSort:
          _prefs.containsPreference(_sortPref) &&
              BookBrowseViewModel.titleSorts.contains(saved)
          ? saved
          : LibrarySortBy.dateAdded,
    );
    _vm.addListener(_onChanged);
    _prefs.addListener(_onChanged);
    _vm.load();
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    _vm.removeListener(_onChanged);
    _vm.dispose();
    _initialFocusNode.dispose();
    _scopeFocusNode.dispose();
    _tabsFocusNode.dispose();
    _toolbarFocusNode.dispose();
    for (final node in _railNodes.values) {
      node.dispose();
    }
    _scrollController.dispose();
    disposeGridFocusNodes();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cleanupGridFocusNodes(_vm.paneItems.length);
    });
    if (!PlatformDetection.useMobileUi && !_vm.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _vm.isLoading ||
            !canClaimInitialFocus(context) ||
            LeftSidebar.isFocusedNotifier.value ||
            TopToolbar.isFocusedNotifier.value) {
          return;
        }
        // The first load lands on the top of the content. After that, an
        // update only steps in when a rebuild took the focused card away,
        // never while the viewer is somewhere on the page.
        if (_landedOnContent && !bookFocusIsLost) return;
        _landedOnContent = true;
        _focusDefault();
      });
    }
  }

  /// The Continue row if there's one, else the first card. The toolbar
  /// sits at the far right, so landing there reads as focus jumping away.
  void _focusDefault() {
    final first = gridItemFocusNodes[0];
    if (!_hasResume && _tab == 0 && first != null && first.context != null) {
      first.requestFocus();
      return;
    }
    _coordinator.focusFirst();
  }

  bool get _wide => !PlatformDetection.useMobileUi;

  bool get _hasResume => _vm.resumeRow?.items.isNotEmpty ?? false;

  FocusNode _gridNode(int index) =>
      getGridItemFocusNode(index, prefix: 'bookGrid');

  void _openItem(AggregatedItem item) =>
      openBookLibraryItem(context, item, libraryId: widget.libraryId);

  void _readOrListen(AggregatedItem item) =>
      readOrListenBook(context, item, isAudiobook: _vm.isAudiobookItem(item));

  void _onItemLongPress(AggregatedItem item) {
    if (item.type == 'BookSeries' || item.type == 'Genre') return;
    showContextMenu(context, item, onChanged: () => setState(() {}));
  }

  bool _moveVertical(int fromIndex, bool isUp) =>
      moveBookFocus(_coordinator, fromIndex, isUp);

  FocusNode _railNode(String id) =>
      _railNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'bookRail:$id'));

  String get _selectedRailId {
    if (_tab == 1) return 'discover';
    if (_vm.pane != BookPane.titles) return 'pane:${_vm.pane.name}';
    return 'scope:${_vm.scope.name}';
  }

  void _focusRail() {
    final node = _railNodes[_selectedRailId];
    if (node != null && node.context != null) node.requestFocus();
  }

  void _focusContent() {
    if (_tab == 1) {
      // Discover isn't in the focus chain since it lays out its own stops.
      FocusManager.instance.primaryFocus?.focusInDirection(
        TraversalDirection.right,
      );
      return;
    }
    final last = lastFocusedGridIndex;
    final node = last == null ? null : gridItemFocusNodes[last];
    if (node != null && node.context != null) {
      node.requestFocus();
      return;
    }
    _focusDefault();
  }

  void _revealFocused(FocusNode node) {
    final ctx = node.context;
    if (ctx == null) return;
    unawaited(
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _showPane(BookPane pane) {
    setState(() {
      _tab = 0;
      lastFocusedGridIndex = null;
    });
    _vm.setPane(pane);
    _scrollToTop();
  }

  void _showTitles(BookScope scope) {
    setState(() {
      _tab = 0;
      lastFocusedGridIndex = null;
    });
    _vm.setScope(scope);
    _vm.setPane(BookPane.titles);
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final current = _vm.titleSort;
    final picked = await showFocusRestoringDialog<LibrarySortBy>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.sortBy),
        children: [
          for (final sort in BookBrowseViewModel.titleSorts)
            FocusableWrapper(
              autofocus: sort == current,
              borderRadius: 8,
              disableScale: true,
              onSelect: () => Navigator.of(dialogContext).pop(sort),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(librarySortLabel(sort, l10n))),
                    if (sort == current)
                      Icon(Icons.check_rounded, color: AppColorScheme.accent),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _vm.setTitleSort(picked);
    unawaited(_prefs.set(_sortPref, picked));
  }

  KeyEventResult _onGridKey(int index, int columns, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final count = _vm.paneItems.length;
    if (key.isLeftKey && index % columns == 0) {
      _focusRail();
      return KeyEventResult.handled;
    }
    if (key.isRightKey &&
        (index % columns == columns - 1 || index == count - 1)) {
      return KeyEventResult.handled;
    }
    if (key.isUpKey && index < columns) {
      return _moveVertical(_gridEntryIndex, true)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key.isDownKey && index + columns >= count) {
      if (_vm.paneHasMore) {
        _vm.loadMorePane();
      } else if (index ~/ columns < (count - 1) ~/ columns) {
        // Nothing sits under this card in a ragged last row, so step onto
        // the row's last card rather than out of the grid.
        gridItemFocusNodes[count - 1]?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  IconData _scopeIcon(BookScope scope) => switch (scope) {
    BookScope.all => Icons.library_books_outlined,
    BookScope.books => Icons.menu_book_rounded,
    BookScope.audiobooks => Icons.headphones_rounded,
    BookScope.comics => Icons.auto_stories_rounded,
  };

  String _scopeLabel(AppLocalizations l10n, BookScope scope) =>
      scope == BookScope.all ? l10n.allTitles : bookScopeLabel(l10n, scope);

  static const _browsePanes = [
    BookPane.series,
    BookPane.authors,
    BookPane.genres,
    BookPane.collections,
    BookPane.favorites,
  ];

  (String label, IconData icon, int count) _paneSummary(
    AppLocalizations l10n,
    BookPane pane,
  ) => switch (pane) {
    BookPane.series => (l10n.series, Icons.layers_outlined, _vm.seriesCount),
    BookPane.authors => (
      l10n.authors,
      Icons.person_outline_rounded,
      _vm.authorCount,
    ),
    BookPane.genres => (l10n.genres, Icons.sell_outlined, _vm.genreCount),
    BookPane.collections => (
      l10n.collections,
      Icons.collections_bookmark_outlined,
      _vm.collectionCount,
    ),
    BookPane.favorites => (
      l10n.favorites,
      Icons.favorite_border_rounded,
      _vm.favoriteCount,
    ),
    BookPane.titles => (
      _scopeLabel(l10n, _vm.scope),
      _scopeIcon(_vm.scope),
      _vm.titleCountFor(_vm.scope),
    ),
  };

  String _countLabel(BookPane pane, int count) =>
      pane == BookPane.collections && _vm.collectionCountIsFloor
      ? '$count+'
      : '$count';

  /// The browse lists that hold anything, each with its count. On the phone
  /// strip, picking the open one again goes back to the titles.
  List<BookBrowseEntry> _browseEntries(
    AppLocalizations l10n, {
    required bool toggles,
  }) => [
    for (final pane in _browsePanes)
      if (_paneSummary(l10n, pane) case (final label, final icon, final count)
          when count > 0)
        BookBrowseEntry(
          id: 'pane:${pane.name}',
          label: label,
          icon: icon,
          count: _countLabel(pane, count),
          selected: _tab == 0 && _vm.pane == pane,
          onSelect: () => _showPane(
            toggles && _tab == 0 && _vm.pane == pane ? BookPane.titles : pane,
          ),
        ),
  ];

  List<BookRailSection> _railSections(
    AppLocalizations l10n, {
    required bool showDiscover,
  }) {
    final scopes = _vm.isMixedLibrary
        ? _vm.availableScopes
        : const [BookScope.all];
    final browse = _browseEntries(l10n, toggles: false);
    return [
      BookRailSection(
        header: l10n.titles,
        entries: [
          for (final scope in scopes)
            BookBrowseEntry(
              id: 'scope:${scope.name}',
              label: _scopeLabel(l10n, scope),
              icon: _scopeIcon(scope),
              count: '${_vm.titleCountFor(scope)}',
              selected: _selectedRailId == 'scope:${scope.name}',
              onSelect: () => _showTitles(scope),
            ),
        ],
      ),
      if (browse.isNotEmpty)
        BookRailSection(header: l10n.browse, entries: browse),
      if (showDiscover)
        BookRailSection(
          entries: [
            BookBrowseEntry(
              id: 'discover',
              label: l10n.discover,
              icon: Icons.explore_outlined,
              selected: _tab == 1,
              onSelect: () => setState(() => _tab = 1),
            ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => RequestInitialFocus(
    targetNode: _initialFocusNode,
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: '/books/${widget.libraryId}',
        showBackButton: true,
        child: _vm.isLoading
            ? const SkeletonLibraryGrid(
                cardWidth: 160,
                aspectRatio: 2 / 3,
              )
            : RefreshIndicator(
                onRefresh: _vm.load,
                child: BottomNavPadded(
                  fallback: 120,
                  builder: (_, bottom) {
                    final showDiscover = _prefs.get(
                      UserPreferences.showBookDiscoverTab,
                    );
                    // Turning the setting off while Discover is open drops
                    // back to the library.
                    if (!showDiscover) _tab = 0;
                    return _wide
                        ? _buildWide(context, bottom, showDiscover: showDiscover)
                        : _buildPhone(
                            context,
                            bottom,
                            showDiscover: showDiscover,
                          );
                  },
                ),
              ),
      ),
    );
  }

  /// Pages the list in as the viewer nears its end.
  Widget _pagingScrollView(List<Widget> slivers) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 900) {
          _vm.loadMorePane();
        }
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  /// Rebuilds the vertical focus chain for this build and returns where each
  /// stop sits in it, -1 for a stop that isn't there.
  ({int tabs, int resume, int scope, int toolbar}) _focusChain({
    required bool showTabs,
    required bool showScope,
  }) {
    final entries = <RowFocusEntry>[
      if (showTabs)
        RowFocusEntry.node(_tabsFocusNode, containerKey: _tabsContainerKey),
      if (_tab == 0) ...[
        if (_hasResume)
          RowFocusEntry.row(
            _continueRowKey,
            containerKey: _continueContainerKey,
          ),
        if (showScope)
          RowFocusEntry.node(_scopeFocusNode, containerKey: _scopeContainerKey),
        RowFocusEntry.node(
          _toolbarFocusNode,
          containerKey: _toolbarContainerKey,
        ),
        if (_vm.paneItems.isNotEmpty) RowFocusEntry.node(_gridNode(0)),
      ],
    ];
    _coordinator.entries = entries;
    var index = 0;
    final tabs = showTabs ? index++ : -1;
    final inContent = _tab == 0;
    final resume = inContent && _hasResume ? index++ : -1;
    final scope = inContent && showScope ? index++ : -1;
    final toolbar = inContent ? index++ : -1;
    _gridEntryIndex = inContent && _vm.paneItems.isNotEmpty ? index : -1;
    return (tabs: tabs, resume: resume, scope: scope, toolbar: toolbar);
  }

  Widget _buildPhone(
    BuildContext context,
    double bottom, {
    required bool showDiscover,
  }) {
    final l10n = AppLocalizations.of(context);
    final topReserve = MediaQuery.paddingOf(context).top + 56;
    final showScope =
        _vm.isMixedLibrary && _tab == 0 && _vm.pane == BookPane.titles;
    final chain = _focusChain(showTabs: showDiscover, showScope: showScope);
    final browse = _browseEntries(l10n, toggles: true);

    return _pagingScrollView([
      SliverToBoxAdapter(child: SizedBox(height: topReserve)),
      if (showDiscover)
        SliverToBoxAdapter(
          child: Padding(
            key: _tabsContainerKey,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SlidingPillTabs(
              labels: [l10n.library, l10n.discover],
              selectedIndex: _tab,
              onChanged: (v) => setState(() => _tab = v),
              focusNode: _tabsFocusNode,
              onVerticalNavigation: (isUp) => _moveVertical(chain.tabs, isUp),
            ),
          ),
        ),
      if (_tab == 1)
        SliverToBoxAdapter(
          child: BookDiscoverTab(
            libraryId: widget.libraryId,
            isAudiobook: _vm.isAudiobookLibrary,
          ),
        )
      else ...[
        if (_hasResume)
          SliverToBoxAdapter(
            child: _buildContinue(
              inset: 16,
              tileWidth: 300,
              entryIndex: chain.resume,
            ),
          ),
        if (browse.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: BookBrowseTiles(entries: browse),
            ),
          ),
        if (showScope)
          SliverToBoxAdapter(
            child: Padding(
              key: _scopeContainerKey,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: BookScopeFilter(
                value: _vm.scope,
                onChanged: _vm.setScope,
                availableScopes: _vm.availableScopes,
                focusNode: _scopeFocusNode,
                onVerticalNavigation: (isUp) =>
                    _moveVertical(chain.scope, isUp),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            key: _toolbarContainerKey,
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: _buildToolbar(l10n, wide: false, entryIndex: chain.toolbar),
          ),
        ),
        ..._buildPaneSlivers(
          l10n,
          wide: false,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ],
      SliverToBoxAdapter(child: SizedBox(height: bottom)),
    ]);
  }

  Widget _buildWide(
    BuildContext context,
    double bottom, {
    required bool showDiscover,
  }) {
    final l10n = AppLocalizations.of(context);
    final topReserve = MediaQuery.paddingOf(context).top + 56;
    final chain = _focusChain(showTabs: false, showScope: false);

    return Padding(
      padding: EdgeInsets.only(left: bookSidebarInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: AppColorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: BookLibraryRail(
              title: _vm.libraryName.isNotEmpty
                  ? _vm.libraryName
                  : l10n.books,
              subtitle: l10n.spotlightTitlesCount(_vm.titleCount),
              sections: _railSections(l10n, showDiscover: showDiscover),
              focusNodeFor: _railNode,
              onNavigateRight: _focusContent,
              onNavigateLeft: focusBookSidebar,
              topInset: topReserve,
            ),
          ),
          Expanded(
            child: _pagingScrollView([
              SliverToBoxAdapter(child: SizedBox(height: topReserve)),
              if (_tab == 1)
                SliverToBoxAdapter(
                  child: BookDiscoverTab(
                    libraryId: widget.libraryId,
                    isAudiobook: _vm.isAudiobookLibrary,
                  ),
                )
              else ...[
                if (_hasResume)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildContinue(
                        inset: 24,
                        tileWidth: 340,
                        entryIndex: chain.resume,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    key: _toolbarContainerKey,
                    padding: const EdgeInsets.fromLTRB(24, 24, 48, 12),
                    child: _buildToolbar(
                      l10n,
                      wide: true,
                      entryIndex: chain.toolbar,
                    ),
                  ),
                ),
                ..._buildPaneSlivers(
                  l10n,
                  wide: true,
                  // Room for a focused card to grow without covering the
                  // toolbar.
                  padding: const EdgeInsets.fromLTRB(24, 20, 48, 0),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: math.max(bottom, 48))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildContinue({
    required double inset,
    required double tileWidth,
    required int entryIndex,
  }) {
    final row = _vm.resumeRow!;
    return BookShelfRow(
      key: const ValueKey('bookContinue'),
      row: row,
      title: row.title,
      hubKey: 'books_${widget.libraryId}_resume',
      rowKey: _continueRowKey,
      containerKey: _continueContainerKey,
      tileWidth: tileWidth,
      leadingInset: inset,
      onVerticalNavigation: (isUp) => _moveVertical(entryIndex, isUp),
      onLeftEdge: _wide ? _focusRail : focusBookSidebar,
      onItemTap: _openItem,
      onItemPlay: _readOrListen,
      onItemLongPress: _onItemLongPress,
      imageUrlFor: _vm.bookImageUrl,
      subtitleFor: _vm.bookSubtitle,
      isAudiobookFor: _vm.isAudiobookItem,
      remainingFor: _vm.remainingFor,
    );
  }

  bool get _paneListsTitles =>
      _vm.pane == BookPane.titles || _vm.pane == BookPane.favorites;

  bool get _showsList =>
      _paneListsTitles && _prefs.get(UserPreferences.bookLibraryListView);

  Widget _buildToolbar(
    AppLocalizations l10n, {
    required bool wide,
    required int entryIndex,
  }) {
    final onSurface = AppColorScheme.onSurface;
    final (heading, _, count) = _paneSummary(l10n, _vm.pane);
    final listView = _prefs.get(UserPreferences.bookLibraryListView);

    final buttons =
        <({String label, IconData icon, bool iconOnly, VoidCallback onSelect})>[
      if (wide)
        (
          label: l10n.search,
          icon: Icons.search_rounded,
          iconOnly: false,
          onSelect: () => context.push(
            Destinations.searchInLibrary(widget.libraryId),
          ),
        ),
      if (_paneListsTitles) ...[
        (
          label: librarySortLabel(_vm.titleSort, l10n),
          icon: Icons.sort_rounded,
          iconOnly: false,
          onSelect: _pickSort,
        ),
        (
          label: l10n.layout,
          icon: listView ? Icons.grid_view_rounded : Icons.view_list_rounded,
          iconOnly: true,
          onSelect: () => unawaited(
            _prefs.set(UserPreferences.bookLibraryListView, !listView),
          ),
        ),
      ],
      if (!wide && _vm.pane != BookPane.titles)
        (
          label: l10n.close,
          icon: Icons.close_rounded,
          iconOnly: true,
          onSelect: () => _showPane(BookPane.titles),
        ),
    ];

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: wide ? 22 : 17,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _countLabel(_vm.pane, count),
                style: TextStyle(
                  fontSize: 14,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          FocusableWrapper(
            // The first button stands for the whole bar in the focus chain.
            focusNode: i == 0 ? _toolbarFocusNode : null,
            borderRadius: 20,
            disableScale: true,
            semanticLabel: buttons[i].iconOnly ? buttons[i].label : null,
            onSelect: buttons[i].onSelect,
            onNavigateUp: () => _moveVertical(entryIndex, true),
            onNavigateDown: () => _moveVertical(entryIndex, false),
            onNavigateLeft: i == 0 && wide ? _focusRail : null,
            child: _ToolbarButton(
              label: buttons[i].label,
              icon: buttons[i].icon,
              iconOnly: buttons[i].iconOnly,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildPaneSlivers(
    AppLocalizations l10n, {
    required bool wide,
    required EdgeInsets padding,
  }) {
    final items = _vm.paneItems;
    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _vm.paneLoading
              ? const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const BookEmptyState(),
        ),
      ];
    }
    final loadingMore = _vm.paneLoading
        ? const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        : null;

    if (_showsList) {
      return [
        SliverPadding(
          padding: padding,
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (_, index) =>
                _buildListTile(l10n, items[index], index, wide: wide),
          ),
        ),
        ?loadingMore,
      ];
    }

    final pane = _vm.pane;
    final aspectRatio = switch (pane) {
      BookPane.genres => 16 / 9,
      BookPane.authors => 1.0,
      _ => 2 / 3,
    };
    final hasSubtitle = pane != BookPane.genres && pane != BookPane.authors;
    return [
      SliverPadding(
        padding: padding,
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final target = pane == BookPane.genres ? 220.0 : 150.0;
            final gap = wide ? 20.0 : 12.0;
            final columns = wide
                ? math.max(2, ((width + gap) / (target + gap)).floor())
                : (pane == BookPane.genres ? 2 : 3);
            // A focused card grows past its cell, so the gap widens to fit it.
            final spacing = wide
                ? math.max(
                    gap,
                    MediaCard.focusGap((width - gap * (columns - 1)) / columns),
                  )
                : gap;
            final cellWidth = (width - spacing * (columns - 1)) / columns;
            final cellHeight = MediaCard.layoutHeight(
              context,
              width: cellWidth,
              aspectRatio: aspectRatio,
              hasSubtitle: hasSubtitle,
            );
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: wide ? 26 : 18,
                childAspectRatio: cellWidth / cellHeight,
              ),
              itemCount: items.length,
              itemBuilder: (_, index) => _buildGridItem(
                items[index],
                index,
                columns: columns,
                aspectRatio: aspectRatio,
                wide: wide,
              ),
            );
          },
        ),
      ),
      ?loadingMore,
    ];
  }

  Widget _buildGridItem(
    AggregatedItem item,
    int index, {
    required int columns,
    required double aspectRatio,
    required bool wide,
  }) {
    final node = _gridNode(index);
    final onKey = wide
        ? (FocusNode _, KeyEvent event) => _onGridKey(index, columns, event)
        : null;
    final onFocus = wide ? () => _revealFocused(node) : null;

    if (_paneListsTitles) {
      final isAudio = _vm.isAudiobookItem(item);
      return BookCard(
        item: item,
        isAudiobook: isAudio,
        subtitle: _vm.bookSubtitle(item),
        imageUrl: _vm.bookImageUrl(item),
        remaining: isAudio ? _vm.remainingFor(item) : null,
        showComicBadge: _vm.isComicItem(item) && _vm.isMixedLibrary,
        focusNode: node,
        onFocus: onFocus,
        onKeyEvent: onKey,
        onTap: () => _openItem(item),
        onLongPress: () => _onItemLongPress(item),
      );
    }

    final pane = _vm.pane;
    return MediaCard(
      title: item.name,
      subtitle: pane == BookPane.series || pane == BookPane.collections
          ? _vm.bookSubtitle(item)
          : null,
      imageUrl: _vm.bookImageUrl(item),
      width: double.infinity,
      aspectRatio: aspectRatio,
      // Authors come back as artists, and only a person is drawn round.
      itemType: pane == BookPane.authors ? 'Person' : item.type,
      isFavorite: item.isFavorite,
      focusNode: node,
      onFocus: onFocus,
      onKeyEvent: onKey,
      onTap: () => _openItem(item),
      onLongPress: pane == BookPane.collections
          ? () => _onItemLongPress(item)
          : null,
    );
  }

  Widget _buildListTile(
    AppLocalizations l10n,
    AggregatedItem item,
    int index, {
    required bool wide,
  }) {
    final isAudio = _vm.isAudiobookItem(item);
    final pct = item.playedPercentage ?? 0;
    return BookListTile(
      title: item.name,
      subtitle: _vm.bookSubtitle(item),
      imageUrl: _vm.bookImageUrl(item),
      isAudio: isAudio,
      isComic: _vm.isComicItem(item),
      progress: pct > 0 ? (pct / 100).clamp(0.0, 1.0) : null,
      meta: bookProgressMeta(
        l10n,
        isAudiobook: isAudio,
        playedPercentage: pct,
        remaining: isAudio ? _vm.remainingFor(item) : null,
      ),
      focusNode: _gridNode(index),
      onKeyEvent: wide ? (_, event) => _onGridKey(index, 1, event) : null,
      onTap: () => _openItem(item),
      onLongPress: () => _onItemLongPress(item),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool iconOnly;

  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.iconOnly,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = AppColorScheme.onSurface;
    final border = Border.all(color: onSurface.withValues(alpha: 0.14));
    if (iconOnly) {
      return Tooltip(
        message: label,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, border: border),
          child: Icon(icon, size: 20, color: onSurface),
        ),
      );
    }
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: border,
        borderRadius: AppRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: onSurface),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
