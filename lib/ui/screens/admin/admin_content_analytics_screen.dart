import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../util/error_message.dart';
import 'libraries/admin_libraries_screen.dart';
import 'providers/admin_media_analytics_provider.dart';
import 'widgets/admin_form_styles.dart';
import 'widgets/admin_media_summary_section.dart';

// Categorical slots in an order that passes the colorblind checks on the dark
// surface. Past five, values fold into Other.
const _seriesColors = [
  Color(0xFF0096C9),
  Color(0xFFD95926),
  Color(0xFF9085E9),
  Color(0xFFC98500),
  Color(0xFFD55181),
];
const _otherColor = Color(0xFF6B6F76);

// One blue from dark to light, for values with an order like decades.
const _ordinalColors = [
  Color(0xFF184F95),
  Color(0xFF256ABF),
  Color(0xFF3987E5),
  Color(0xFF6DA7EC),
  Color(0xFF9EC5F4),
  Color(0xFFCDE2FB),
];

const _allKey = 'all';

class AdminContentAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminContentAnalyticsScreen({super.key});

  @override
  ConsumerState<AdminContentAnalyticsScreen> createState() =>
      _AdminContentAnalyticsScreenState();
}

class _AdminContentAnalyticsScreenState
    extends ConsumerState<AdminContentAnalyticsScreen> {
  String _selectedKey = _allKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final analyticsAsync = ref.watch(adminMediaAnalyticsProvider);

    return analyticsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.adminMediaAnalyticsLoadFailed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              describeError(error, l10n),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(adminMediaAnalyticsProvider),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
      data: (state) {
        final data = state.data;
        if (data == null) {
          final percentage = (state.progress * 100).toInt();
          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    l10n.adminAnalyticsLoadingProgress(percentage),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 6,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            await reloadAdminMediaAnalytics(ref);
            await ref.read(adminMediaAnalyticsProvider.future);
          },
          child: _buildBody(context, state, data),
        );
      },
    );
  }

  void _open(AdminAnalyticsQuery query) => context.push(query.location);

  Future<void> _pickLibrary(
    List<_LibraryEntry> entries,
    String selectedKey,
  ) async {
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: _LibraryList(
            entries: entries,
            selectedKey: selectedKey,
            onSelected: (key) => Navigator.pop(sheetContext, key),
          ),
        ),
      ),
    );
    if (key != null && mounted) setState(() => _selectedKey = key);
  }

  Widget _buildBody(
    BuildContext context,
    AdminAnalyticsLoadingState state,
    AdminMediaAnalyticsDetail analytics,
  ) {
    final l10n = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isMobileLayout = mediaQuery.size.width < 700;
    final bottomInset = isMobileLayout
      ? mediaQuery.padding.bottom + 28
      : mediaQuery.padding.bottom + 8;

    final libraries = analytics.libraries;
    // A library that went away since it was picked falls back to all of them.
    final selected = libraries
        .where((library) => library.itemId == _selectedKey)
        .firstOrNull;
    final grandTotal = libraries.fold<int>(
      0,
      (sum, library) => sum + library.totalTrackedItems,
    );
    final largest = libraries.fold<int>(
      0,
      (max, library) =>
          library.totalTrackedItems > max ? library.totalTrackedItems : max,
    );
    final entries = [
      _LibraryEntry(
        key: _allKey,
        title: l10n.allLibraries,
        icon: Icons.dashboard_outlined,
        count: grandTotal,
        bar: _StackedBar(
          height: 4,
          segments: [
            for (var i = 0; i < libraries.length; i++)
              _Segment(
                label: libraries[i].name,
                count: libraries[i].totalTrackedItems,
                color: _categoricalColor(i),
              ),
          ],
        ),
      ),
      for (var i = 0; i < libraries.length; i++)
        _LibraryEntry(
          key: libraries[i].itemId,
          title: libraries[i].name,
          icon: AdminLibrariesScreen.iconForType(libraries[i].collectionType),
          count: libraries[i].totalTrackedItems,
          bar: _ShareBar(
            fraction: largest == 0
                ? 0
                : libraries[i].totalTrackedItems / largest,
            color: _categoricalColor(i),
            height: 4,
          ),
        ),
    ];
    final selectedEntry = entries.firstWhere(
      (entry) => entry.key == (selected?.itemId ?? _allKey),
    );

    // On a phone the picker already names the library, so the detail leaves
    // its header out.
    Widget detail(bool wide) => selected == null
        ? _AllDetail(
            showHeader: wide,
            libraries: libraries,
            technicalProfile: analytics.technicalProfile,
            total: grandTotal,
            progress: state.progress,
            onOpen: _open,
            onSelect: (key) => setState(() => _selectedKey = key),
          )
        : _LibraryDetail(
            showHeader: wide,
            library: selected,
            share: grandTotal == 0
                ? 0
                : selected.totalTrackedItems / grandTotal,
            progress: state.progress,
            onOpen: _open,
          );

    final reload = state.isComplete
        ? () => reloadAdminMediaAnalytics(ref)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomInset),
          children: [
            Row(
              children: [
                Expanded(
                  child: adminScreenHeader(
                    context,
                    title: l10n.adminDrawerAnalytics,
                    subtitle: l10n.adminPageDescAnalytics,
                    icon: Icons.insights_outlined,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 16),
                  child: wide
                      ? OutlinedButton.icon(
                          onPressed: reload,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(l10n.refresh),
                        )
                      : IconButton.outlined(
                          tooltip: l10n.refresh,
                          onPressed: reload,
                          icon: const Icon(Icons.refresh),
                        ),
                ),
              ],
            ),
            if (!state.isComplete)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 4,
                  ),
                ),
              ),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 240,
                    child: adminListCard(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _LibraryList(
                          entries: entries,
                          selectedKey: selectedEntry.key,
                          onSelected: (key) =>
                              setState(() => _selectedKey = key),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: detail(wide)),
                ],
              )
            else ...[
              _LibraryPicker(
                entry: selectedEntry,
                onTap: () => _pickLibrary(entries, selectedEntry.key),
              ),
              const SizedBox(height: 16),
              detail(wide),
            ],
          ],
        );
      },
    );
  }
}

Color _categoricalColor(int index) =>
    index < _seriesColors.length ? _seriesColors[index] : _otherColor;

Color _ordinalColor(int index, int count) => _ordinalColors[count <= 1
    ? 2
    : (index * (_ordinalColors.length - 1) / (count - 1)).round()];

Color _muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);

String _percent(int count, int total) =>
    total == 0 ? '0.0' : (count / total * 100).toStringAsFixed(1);

/// Spaces [sections] 16 apart, so a missing card leaves no gap.
List<Widget> _spaced(List<Widget> sections) => [
  for (var i = 0; i < sections.length; i++) ...[
    if (i > 0) const SizedBox(height: 16),
    sections[i],
  ],
];

typedef _OpenCategory = void Function(
  AdminAnalyticsDimension dimension,
  List<String> values,
  String title,
);

class _AllDetail extends StatelessWidget {
  const _AllDetail({
    required this.showHeader,
    required this.libraries,
    required this.technicalProfile,
    required this.total,
    required this.progress,
    required this.onOpen,
    required this.onSelect,
  });

  final bool showHeader;
  final List<AdminLibraryMediaAnalytics> libraries;
  final AdminTechnicalProfile technicalProfile;
  final int total;
  final double progress;
  final ValueChanged<AdminAnalyticsQuery> onOpen;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void open(
      AdminAnalyticsDimension dimension,
      List<String> values,
      String title,
    ) => onOpen(
      AdminAnalyticsQuery(dimension: dimension, values: values, title: title),
    );

    final totals = {
      for (final metric in adminMetricsForCollectionType(null))
        metric.key: libraries.fold<int>(
          0,
          (sum, library) => sum + library.countFor(metric.key),
        ),
    };
    final tiles = [
      for (final MapEntry(:key, value: count) in totals.entries)
        if (count > 0)
          _StatTile(
            icon: adminMediaIconForKey(key),
            label: adminMediaMetricLabel(l10n, key),
            value: formatAdminCount(count),
            onTap: () => open(
              AdminAnalyticsDimension.type,
              [key],
              adminMediaMetricLabel(l10n, key),
            ),
          ),
    ];
    final codecCards = _codecCards(
      l10n,
      containersTitle: l10n.analyticsContainers,
      containers: technicalProfile.containers,
      videoCodecs: technicalProfile.videoCodecs,
      audioCodecs: technicalProfile.audioCodecs,
      open: open,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced([
        if (showHeader)
          _DetailHeader(
            icon: Icons.dashboard_customize_outlined,
            title: l10n.allLibraries,
            subtitle: l10n.analyticsLibrariesCount(libraries.length),
            total: total,
          ),
        if (tiles.isNotEmpty) _CardGrid(minWidth: 150, gap: 12, children: tiles),
        if (libraries.isNotEmpty)
          _CompositionCard(
            title: l10n.analyticsLibraryShare,
            segments: [
              for (var i = 0; i < libraries.length; i++)
                _Segment(
                  label: libraries[i].name,
                  count: libraries[i].totalTrackedItems,
                  color: _categoricalColor(i),
                  onTap: () => onSelect(libraries[i].itemId),
                ),
            ],
          ),
        if (libraries.any((library) => library.insightsPending))
          _LoadingCard(progress: progress),
        if (codecCards.isNotEmpty) _CardGrid(minWidth: 240, children: codecCards),
      ]),
    );
  }
}

class _LibraryDetail extends StatelessWidget {
  const _LibraryDetail({
    required this.showHeader,
    required this.library,
    required this.share,
    required this.progress,
    required this.onOpen,
  });

  final bool showHeader;
  final AdminLibraryMediaAnalytics library;
  final double share;
  final double progress;
  final ValueChanged<AdminAnalyticsQuery> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final insights = library.insights;
    final total = library.totalTrackedItems;
    void open(
      AdminAnalyticsDimension dimension,
      List<String> values,
      String title,
    ) => onOpen(
      AdminAnalyticsQuery(
        libraryId: library.itemId,
        dimension: dimension,
        values: values,
        title: title,
      ),
    );

    MapEntry<String, int>? topOf(Map<String, int> values) => values.entries
        .fold<MapEntry<String, int>?>(
          null,
          (best, entry) =>
              best == null || entry.value > best.value ? entry : best,
        );
    String shareOf(int count, Map<String, int> values) =>
        l10n.analyticsShareOfItems(
          (count /
                  values.values.fold<int>(0, (sum, value) => sum + value) *
                  100)
              .round()
              .toString(),
        );

    final years = [
      for (final year in insights.years.keys) ?int.tryParse(year),
    ]..sort();
    final yearSpan = years.isEmpty
        ? null
        : years.first == years.last
            ? '${years.first}'
            : '${years.first}-${years.last}';
    final topRating = topOf(insights.ratings);
    final topRuntime = topOf(insights.runtimeBuckets);

    final tiles = [
      for (final metric in adminMetricsForCollectionType(library.collectionType))
        if (library.countFor(metric.key) > 0)
          _StatTile(
            icon: adminMediaIconForKey(metric.key),
            label: adminMediaMetricLabel(l10n, metric.key),
            value: formatAdminCount(library.countFor(metric.key)),
            onTap: () => open(
              AdminAnalyticsDimension.type,
              [metric.key],
              adminMediaMetricLabel(l10n, metric.key),
            ),
          ),
      if (yearSpan != null)
        _StatTile(
          icon: Icons.calendar_month_outlined,
          label: l10n.analyticsReleaseYears,
          value: yearSpan,
          onTap: () => open(AdminAnalyticsDimension.year, const [], yearSpan),
        ),
      if (topRating != null)
        _StatTile(
          icon: Icons.shield_outlined,
          label: l10n.analyticsTopRating,
          value: topRating.key,
          note: shareOf(topRating.value, insights.ratings),
          onTap: () =>
              open(AdminAnalyticsDimension.rating, [topRating.key], topRating.key),
        ),
      if (topRuntime != null)
        _StatTile(
          icon: Icons.timer_outlined,
          label: l10n.analyticsTypicalRuntime,
          value: topRuntime.key,
          note: shareOf(topRuntime.value, insights.runtimeBuckets),
          onTap: () => open(
            AdminAnalyticsDimension.runtime,
            [topRuntime.key],
            topRuntime.key,
          ),
        ),
    ];

    final orderedCards = [
      if (insights.runtimeBuckets.isNotEmpty)
        _CompositionCard(
          title: l10n.analyticsRuntimeBuckets,
          segments: _runtimeSegments(
            insights.runtimeBuckets,
            (label, buckets) =>
                open(AdminAnalyticsDimension.runtime, buckets, label),
          ),
        ),
      if (insights.ratings.isNotEmpty)
        _CompositionCard(
          title: l10n.analyticsContentRatings,
          segments: _ranked(
            l10n,
            insights.ratings,
            (keys, label) => open(AdminAnalyticsDimension.rating, keys, label),
          ),
        ),
    ];

    _ShareCard shareCard(
      String title,
      Map<String, int> values,
      AdminAnalyticsDimension dimension,
    ) {
      final shown = (values.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(8)
          .toList();
      final largest = shown.isEmpty ? 0 : shown.first.value;
      return _ShareCard(
        title: title,
        rows: [
          for (final entry in shown)
            _ShareRow(
              label: entry.key,
              count: entry.value,
              fraction: largest == 0 ? 0 : entry.value / largest,
              percent: _percent(entry.value, total),
              onTap: () => open(dimension, [entry.key], entry.key),
            ),
        ],
      );
    }

    final shareCards = [
      if (insights.genres.isNotEmpty)
        shareCard(
          l10n.analyticsTopGenres,
          insights.genres,
          AdminAnalyticsDimension.genre,
        ),
      if (insights.contributors.isNotEmpty)
        shareCard(
          switch ((library.collectionType ?? '').toLowerCase()) {
            'music' => l10n.analyticsTopArtists,
            'books' => l10n.analyticsTopAuthors,
            _ => l10n.analyticsTopContributors,
          },
          insights.contributors,
          AdminAnalyticsDimension.contributor,
        ),
    ];

    final codecCards = _codecCards(
      l10n,
      containersTitle: l10n.analyticsFileFormats,
      containers: insights.containers,
      videoCodecs: insights.videoCodecs,
      audioCodecs: insights.audioCodecs,
      open: open,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced([
        if (showHeader)
          _DetailHeader(
            icon: AdminLibrariesScreen.iconForType(library.collectionType),
            title: library.name,
            subtitle:
                '${AdminLibrariesScreen.labelForType(library.collectionType, l10n)} · '
                '${l10n.analyticsShareOfItems((share * 100).toStringAsFixed(1))}',
            total: total,
          ),
        if (tiles.isNotEmpty) _CardGrid(minWidth: 150, gap: 12, children: tiles),
        if (library.insightsPending) _LoadingCard(progress: progress),
        if (insights.years.isNotEmpty)
          _CompositionCard(
            title: l10n.analyticsReleaseYears,
            segments: _decadeSegments(
              insights.years,
              (label, yearKeys) =>
                  open(AdminAnalyticsDimension.year, yearKeys, label),
            ),
          ),
        if (orderedCards.isNotEmpty) _CardGrid(children: orderedCards),
        if (shareCards.isNotEmpty) _CardGrid(children: shareCards),
        if (codecCards.isNotEmpty) _CardGrid(minWidth: 240, children: codecCards),
      ]),
    );
  }
}

/// The five largest values in their own colors and the rest folded into
/// Other, each opening its items.
List<_Segment> _ranked(
  AppLocalizations l10n,
  Map<String, int> values,
  void Function(List<String> keys, String title) onOpen, {
  bool pretty = false,
}) {
  String labelOf(String key) =>
      pretty ? _prettyToken(key, l10n.unknown, l10n.dolbyVision) : key;
  final sorted = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final rest = [
    for (final entry in sorted.skip(_seriesColors.length)) entry.key,
  ];
  return [
    for (var i = 0; i < sorted.length && i < _seriesColors.length; i++)
      _Segment(
        label: labelOf(sorted[i].key),
        count: sorted[i].value,
        color: _seriesColors[i],
        onTap: () => onOpen([sorted[i].key], labelOf(sorted[i].key)),
      ),
    if (rest.isNotEmpty)
      _Segment(
        label: '${l10n.other}: ${rest.map(labelOf).join(', ')}',
        count: rest.fold<int>(0, (sum, key) => sum + values[key]!),
        color: _otherColor,
        onTap: () => onOpen(rest, l10n.other),
      ),
  ];
}

List<Widget> _codecCards(
  AppLocalizations l10n, {
  required String containersTitle,
  required Map<String, int> containers,
  required Map<String, int> videoCodecs,
  required Map<String, int> audioCodecs,
  required _OpenCategory open,
}) => [
  for (final (title, values, dimension) in [
    (containersTitle, containers, AdminAnalyticsDimension.container),
    (l10n.analyticsVideoCodecs, videoCodecs, AdminAnalyticsDimension.videoCodec),
    (l10n.analyticsAudioCodecs, audioCodecs, AdminAnalyticsDimension.audioCodec),
  ])
    if (values.isNotEmpty)
      _CompositionCard(
        title: title,
        segments: _ranked(
          l10n,
          values,
          (keys, label) => open(dimension, keys, label),
          pretty: true,
        ),
      ),
];

/// Decades oldest first. Past six, the oldest fold into one span so every
/// group keeps its own shade.
List<_Segment> _decadeSegments(
  Map<String, int> years,
  void Function(String label, List<String> yearKeys) onTap,
) {
  final byDecade = <int, Map<String, int>>{};
  for (final entry in years.entries) {
    final year = int.tryParse(entry.key);
    if (year == null) continue;
    byDecade.putIfAbsent(year ~/ 10 * 10, () => {})[entry.key] = entry.value;
  }
  final decades = byDecade.keys.toList()..sort();
  final folded = decades.length > _ordinalColors.length
      ? decades.length - _ordinalColors.length + 1
      : 0;

  final oldest = [for (final d in decades.take(folded)) ...byDecade[d]!.keys];
  final groups = <(String, List<String>)>[
    if (folded > 0)
      (
        '${oldest.map(int.parse).reduce((a, b) => a < b ? a : b)}'
            '-${decades[folded] - 1}',
        oldest,
      ),
    for (final decade in decades.skip(folded))
      ('${decade}s', byDecade[decade]!.keys.toList()),
  ];
  return [
    for (var i = 0; i < groups.length; i++)
      _Segment(
        label: groups[i].$1,
        count: groups[i].$2.fold<int>(0, (sum, key) => sum + years[key]!),
        color: _ordinalColor(i, groups.length),
        onTap: () => onTap(groups[i].$1, groups[i].$2),
      ),
  ];
}

/// Runtime buckets shortest first, with everything under an hour as one.
List<_Segment> _runtimeSegments(
  Map<String, int> buckets,
  void Function(String label, List<String> buckets) onTap,
) {
  const groups = [
    ('<60m', ['<15m', '15-29m', '30-44m', '45-59m']),
    ('60-89m', ['60-89m']),
    ('90-119m', ['90-119m']),
    ('120m+', ['120m+']),
  ];
  final present = [
    for (final (label, keys) in groups)
      if (keys.any(buckets.containsKey))
        (label, [for (final key in keys) if (buckets.containsKey(key)) key]),
  ];
  return [
    for (var i = 0; i < present.length; i++)
      _Segment(
        label: present[i].$1,
        count: present[i].$2.fold<int>(0, (sum, key) => sum + buckets[key]!),
        color: _ordinalColor(i, present.length),
        onTap: () => onTap(present[i].$1, present[i].$2),
      ),
  ];
}

class _Segment {
  const _Segment({
    required this.label,
    required this.count,
    required this.color,
    this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;
}

class _LibraryEntry {
  const _LibraryEntry({
    required this.key,
    required this.title,
    required this.icon,
    required this.count,
    required this.bar,
  });

  final String key;
  final String title;
  final IconData icon;
  final int count;
  final Widget bar;
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.entries,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<_LibraryEntry> entries;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          _LibraryRow(
            entry: entry,
            selected: entry.key == selectedKey,
            onTap: () => onSelected(entry.key),
          ),
      ],
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _LibraryEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: AppRadius.circular(10),
        child: InkWell(
          borderRadius: AppRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      entry.icon,
                      size: 20,
                      color: selected ? scheme.primary : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatAdminCount(entry.count),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _muted(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: ExcludeSemantics(child: entry.bar),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's stand-in for the library list, opening it as a sheet.
class _LibraryPicker extends StatelessWidget {
  const _LibraryPicker({required this.entry, required this.onTap});

  final _LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return adminListCard(
      child: InkWell(
        borderRadius: AppRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _IconTile(icon: entry.icon, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.library,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _muted(context),
                          ),
                        ),
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatAdminCount(entry.count),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _muted(context),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: ExcludeSemantics(child: entry.bar),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.14),
        borderRadius: AppRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: size * 0.55, color: primary),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.total,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _IconTile(icon: icon, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _muted(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formatAdminCount(total),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Lays [children] out in as many equal columns as fit at [minWidth].
class _CardGrid extends StatelessWidget {
  const _CardGrid({
    required this.children,
    this.minWidth = 300,
    this.gap = 16,
  });

  final List<Widget> children;
  final double minWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = ((constraints.maxWidth + gap) / (minWidth + gap)).floor();
        final columns = fit.clamp(1, children.length);
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return adminListCard(
      child: InkWell(
        borderRadius: AppRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _muted(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(
                  note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _muted(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return adminListCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.adminAnalyticsLoadingProgress((progress * 100).toInt()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stacked bar of [segments] with the key under it. Each key row opens the
/// items behind it.
class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.title, required this.segments});

  final String title;
  final List<_Segment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = segments.fold<int>(0, (sum, segment) => sum + segment.count);
    return adminListCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // The key below says the same thing to a screen reader.
            ExcludeSemantics(
              child: _StackedBar(segments: segments, height: 12),
            ),
            const SizedBox(height: 8),
            for (final segment in segments)
              InkWell(
                borderRadius: AppRadius.circular(8),
                onTap: segment.onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: segment.color,
                            borderRadius: AppRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            segment.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatAdminCount(segment.count),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            '${_percent(segment.count, total)}%',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _muted(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Segments side by side in proportion with a 2 px gap, each at least a
/// sliver wide.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.segments, required this.height});

  final List<_Segment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    const gap = 2.0;
    const minWidth = 3.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = segments.fold<int>(0, (sum, s) => sum + s.count);
        final available =
            constraints.maxWidth - gap * (segments.length - 1);
        if (total == 0 || available <= 0) return SizedBox(height: height);
        final widths = [
          for (final segment in segments) available * segment.count / total,
        ];
        // Tiny values keep a sliver, taken from the larger ones.
        var deficit = 0.0;
        var spare = 0.0;
        for (var i = 0; i < widths.length; i++) {
          if (widths[i] < minWidth) {
            deficit += minWidth - widths[i];
            widths[i] = minWidth;
          } else {
            spare += widths[i] - minWidth;
          }
        }
        if (deficit > 0 && spare > deficit) {
          for (var i = 0; i < widths.length; i++) {
            if (widths[i] > minWidth) {
              widths[i] -= (widths[i] - minWidth) / spare * deficit;
            }
          }
        }
        final radius = Radius.circular(height >= 8 ? 4 : 2);
        return Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Tooltip(
                message:
                    '${segments[i].label}: ${formatAdminCount(segments[i].count)} '
                    '(${_percent(segments[i].count, total)}%)',
                child: GestureDetector(
                  onTap: segments[i].onTap,
                  child: Container(
                    width: widths[i],
                    height: height,
                    decoration: BoxDecoration(
                      color: segments[i].color,
                      borderRadius: BorderRadiusDirectional.horizontal(
                        start: i == 0 ? radius : Radius.zero,
                        end: i == segments.length - 1 ? radius : Radius.zero,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.fraction,
    required this.color,
    required this.height,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0.01, 1.0),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadiusDirectional.horizontal(
              end: Radius.circular(height / 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareRow {
  const _ShareRow({
    required this.label,
    required this.count,
    required this.fraction,
    required this.percent,
    required this.onTap,
  });

  final String label;
  final int count;

  /// Against the largest row, so the top bar runs full width.
  final double fraction;

  /// Against every item in the library.
  final String percent;
  final VoidCallback onTap;
}

/// Ranked values with a bar each, for things an item can have several of.
class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.title, required this.rows});

  final String title;
  final List<_ShareRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return adminListCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              InkWell(
                borderRadius: AppRadius.circular(8),
                onTap: row.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatAdminCount(row.count),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _ShareBar(
                              fraction: row.fraction,
                              color: theme.colorScheme.primary,
                              height: 8,
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${row.percent}%',
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _muted(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _prettyToken(
  String token,
  String unknownLabel,
  String dolbyVisionLabel,
) {
  if (token.isEmpty) {
    return unknownLabel;
  }

  final known = <String, String>{
    'h264': 'H.264',
    'avc': 'AVC',
    'h265': 'H.265',
    'hevc': 'HEVC',
    'av1': 'AV1',
    'vp8': 'VP8',
    'vp9': 'VP9',
    'aac': 'AAC',
    'ac3': 'AC3',
    'eac3': 'EAC3',
    'dts': 'DTS',
    'truehd': 'TrueHD',
    'flac': 'FLAC',
    'mp3': 'MP3',
    'opus': 'Opus',
    'vorbis': 'Vorbis',
    'alac': 'ALAC',
    'pcm': 'PCM',
    'wav': 'WAV',
    'mkv': 'MKV',
    'webm': 'WebM',
    'mp4': 'MP4',
    'm4v': 'M4V',
    'mov': 'MOV',
    'avi': 'AVI',
    'ts': 'TS',
    'm2ts': 'M2TS',
    'mpegts': 'MPEG-TS',
    'asf': 'ASF',
    'wmv': 'WMV',
    'sdr': 'SDR',
    'hdr10': 'HDR10',
    'dv': dolbyVisionLabel,
  };

  final normalized = token.trim().toLowerCase();
  final exact = known[normalized];
  if (exact != null) {
    return exact;
  }

  if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(normalized)) {
    return normalized.toUpperCase();
  }

  return token
      .split(RegExp(r'[_\- ]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
