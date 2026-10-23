import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../util/error_message.dart';
import 'providers/admin_media_analytics_provider.dart';
import 'providers/admin_user_providers.dart';
import 'widgets/admin_form_styles.dart';
import 'widgets/admin_media_summary_section.dart';

/// The items behind a category tapped on the analytics page. Each one opens
/// the metadata editor.
class AdminAnalyticsItemsScreen extends ConsumerWidget {
  const AdminAnalyticsItemsScreen({super.key, required this.query});

  final AdminAnalyticsQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(adminAnalyticsItemsProvider(query));
    final library = query.libraryId == null
        ? null
        : ref
            .watch(adminLibrariesProvider)
            .valueOrNull
            ?.where((library) => library.itemId == query.libraryId)
            .firstOrNull;
    final count = itemsAsync.valueOrNull?.length;
    final subtitle = [
      _dimensionTitle(l10n, query.dimension, library?.collectionType),
      query.libraryId == null ? l10n.allLibraries : library?.name,
      if (count != null) l10n.spotlightItemsCount(count),
    ].whereType<String>().join(' · ');
    final header = adminScreenHeader(
      context,
      title: query.title,
      subtitle: subtitle,
      icon: _dimensionIcon(query),
    );
    final padding = EdgeInsets.fromLTRB(
      16,
      20,
      16,
      MediaQuery.paddingOf(context).bottom + 16,
    );

    return itemsAsync.when(
      loading: () => ListView(
        padding: padding,
        children: [
          header,
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (error, _) => ListView(
        padding: padding,
        children: [
          header,
          Text(describeError(error, l10n)),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonal(
              onPressed: () => ref
                ..invalidate(adminLibraryItemsProvider)
                ..invalidate(adminAnalyticsItemsProvider(query)),
              child: Text(l10n.retry),
            ),
          ),
        ],
      ),
      data: (items) => ListView.builder(
        padding: padding,
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index > 0) return _ItemRow(item: items[index - 1]);
          if (items.isNotEmpty) return header;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, Text(l10n.noItems)],
          );
        },
      ),
    );
  }
}

String? _dimensionTitle(
  AppLocalizations l10n,
  AdminAnalyticsDimension dimension,
  String? collectionType,
) => switch (dimension) {
  AdminAnalyticsDimension.type => null,
  AdminAnalyticsDimension.genre => l10n.analyticsTopGenres,
  AdminAnalyticsDimension.contributor => switch ((collectionType ?? '').toLowerCase()) {
    'music' => l10n.analyticsTopArtists,
    'books' => l10n.analyticsTopAuthors,
    _ => l10n.analyticsTopContributors,
  },
  AdminAnalyticsDimension.year => l10n.analyticsReleaseYears,
  AdminAnalyticsDimension.rating => l10n.analyticsContentRatings,
  AdminAnalyticsDimension.runtime => l10n.analyticsRuntimeBuckets,
  AdminAnalyticsDimension.container => l10n.analyticsFileFormats,
  AdminAnalyticsDimension.videoCodec => l10n.analyticsVideoCodecs,
  AdminAnalyticsDimension.audioCodec => l10n.analyticsAudioCodecs,
};

IconData _dimensionIcon(AdminAnalyticsQuery query) => switch (query.dimension) {
  AdminAnalyticsDimension.type =>
    adminMediaIconForKey(query.values.firstOrNull ?? ''),
  AdminAnalyticsDimension.genre => Icons.theater_comedy_outlined,
  AdminAnalyticsDimension.contributor => Icons.person_outline,
  AdminAnalyticsDimension.year => Icons.calendar_month_outlined,
  AdminAnalyticsDimension.rating => Icons.shield_outlined,
  AdminAnalyticsDimension.runtime => Icons.timer_outlined,
  AdminAnalyticsDimension.container => Icons.inventory_2_outlined,
  AdminAnalyticsDimension.videoCodec => Icons.videocam_outlined,
  AdminAnalyticsDimension.audioCodec => Icons.graphic_eq,
};

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final AdminAnalyticsItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final (width, height) = switch (item.type) {
      'Episode' || 'Video' || 'MusicVideo' || 'Photo' => (80.0, 45.0),
      'Audio' || 'MusicAlbum' || 'AudioBook' => (56.0, 56.0),
      _ => (48.0, 72.0),
    };
    final subtitle = [
      item.parentName,
      if (item.year != null) '${item.year}',
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined, size: 20, color: muted),
    );
    final imageItemId = item.imageItemId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: adminListCard(
        child: InkWell(
          borderRadius: AppRadius.circular(18),
          onTap: () => context.push(Destinations.adminMetadata(item.id)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadius.circular(6),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: imageItemId == null
                        ? placeholder
                        : Image.network(
                            GetIt.instance<MediaServerClient>()
                                .imageApi
                                .getPrimaryImageUrl(
                                  imageItemId,
                                  maxHeight: (height * 3).round(),
                                  tag: item.imageTag,
                                ),
                            headers: serverImageHeaders,
                            cacheHeight: (height *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => placeholder,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
