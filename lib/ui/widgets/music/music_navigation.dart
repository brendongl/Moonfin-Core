import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';

/// A music library category, routing to the matching all-items screen.
class MusicCategory {
  final IconData icon;
  final String label;
  final String route;
  const MusicCategory(this.icon, this.label, this.route);
}

List<MusicCategory> musicCategories(BuildContext context, String libraryId) {
  final l10n = AppLocalizations.of(context);
  return [
    MusicCategory(
      Icons.person,
      l10n.artists,
      Destinations.library(libraryId, includeItemTypes: const ['AlbumArtist']),
    ),
    MusicCategory(
      Icons.album,
      l10n.albums,
      Destinations.library(libraryId, includeItemTypes: const ['MusicAlbum']),
    ),
    MusicCategory(
      Icons.music_note,
      l10n.songs,
      Destinations.library(libraryId, includeItemTypes: const ['Audio']),
    ),
    MusicCategory(
      Icons.queue_music,
      l10n.playlists,
      Destinations.library(libraryId, includeItemTypes: const ['Playlist']),
    ),
    MusicCategory(
      Icons.category,
      l10n.genres,
      Destinations.libraryGenresOf(libraryId),
    ),
    MusicCategory(
      Icons.favorite,
      l10n.favorites,
      Destinations.library(libraryId, favorites: true),
    ),
  ];
}

/// Where a music row's See All goes, or null for rows without one.
String? musicSeeAllRoute(String libraryId, String rowId) {
  if (rowId.startsWith('musicalbum_')) {
    return Destinations.library(
      libraryId,
      includeItemTypes: const ['MusicAlbum'],
    );
  } else if (rowId.startsWith('albumartist_')) {
    return Destinations.library(
      libraryId,
      includeItemTypes: const ['AlbumArtist'],
    );
  } else if (rowId.startsWith('musicartist_')) {
    return Destinations.library(
      libraryId,
      includeItemTypes: const ['MusicArtist'],
    );
  } else if (rowId == 'playlists') {
    return Destinations.library(
      libraryId,
      includeItemTypes: const ['Playlist'],
    );
  } else if (rowId.startsWith('favorites_')) {
    // The row itself only holds albums, so keep the same shape behind See All.
    return Destinations.library(
      libraryId,
      includeItemTypes: const ['MusicAlbum'],
      favorites: true,
    );
  }
  return null;
}

/// Plays a song from its album, and opens anything else on its details
/// screen, which starts it when [autoPlay] is set.
void openMusicItem(
  BuildContext context,
  AggregatedItem item, {
  bool autoPlay = false,
}) {
  if (item.type == 'Audio') {
    unawaited(playMusicTrack(context, item));
    return;
  }
  context.push(
    Destinations.item(item.id, serverId: item.serverId, autoPlay: autoPlay),
  );
}

Future<void> playMusicTrack(BuildContext context, AggregatedItem item) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final manager = GetIt.instance<PlaybackManager>();
  var loadingVisible = true;
  void dismissLoading() {
    if (loadingVisible) {
      loadingVisible = false;
      navigator.pop();
    }
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final albumId =
      item.albumId?.isNotEmpty == true ? item.albumId : item.parentId;

  try {
    var tracks = <AggregatedItem>[item];
    var startIndex = 0;

    if (albumId != null && albumId.isNotEmpty) {
      final factory = GetIt.instance<MediaServerClientFactory>();
      final client = item.serverId.isNotEmpty
          ? factory.getClientIfExists(item.serverId) ??
                GetIt.instance<MediaServerClient>()
          : GetIt.instance<MediaServerClient>();

      final data = await client.itemsApi.getItems(
        parentId: albumId,
        includeItemTypes: const ['Audio'],
        sortBy: 'ParentIndexNumber,IndexNumber,SortName',
        fields: 'PrimaryImageAspectRatio,BasicSyncInfo',
      );

      final loadedTracks = (data['Items'] as List?)
              ?.whereType<Map>()
              .map((raw) => raw.cast<String, dynamic>())
              .where((raw) => raw['Id']?.toString().isNotEmpty == true)
              .map((raw) => AggregatedItem(
                    id: raw['Id'].toString(),
                    serverId: item.serverId,
                    rawData: raw,
                  ))
              .toList() ??
          const <AggregatedItem>[];

      if (loadedTracks.isNotEmpty) {
        tracks = loadedTracks;
        final idx = tracks.indexWhere((t) => t.id == item.id);
        if (idx >= 0) {
          startIndex = idx;
        }
      }
    }

    await manager.playItems(tracks, startIndex: startIndex);
    dismissLoading();
    if (context.mounted) {
      context.push(Destinations.audioPlayer);
    }
  } catch (_) {
    dismissLoading();
    await manager.playItems([item]);
    if (context.mounted) {
      context.push(Destinations.audioPlayer);
    }
  }
}

/// Plays the songs under [parentId], an album or a whole library, in a
/// random order.
Future<void> shuffleMusic(
  BuildContext context, {
  required String parentId,
  String? serverId,
}) async {
  final client = GetIt.instance<MediaServerClientFactory>()
      .clientForServerOrActive(serverId);
  try {
    final response = await client.itemsApi.getItems(
      parentId: parentId,
      includeItemTypes: const ['Audio'],
      recursive: true,
      sortBy: 'Random',
      limit: 300,
      fields: 'PrimaryImageAspectRatio,BasicSyncInfo',
    );
    final tracks = ((response['Items'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) => AggregatedItem(
              id: raw['Id']?.toString() ?? '',
              serverId: client.baseUrl,
              rawData: raw.cast<String, dynamic>(),
            ))
        .where((track) => track.id.isNotEmpty)
        .toList();
    if (tracks.isEmpty) return;
    await GetIt.instance<PlaybackManager>().playItems(tracks);
    if (context.mounted) context.push(Destinations.audioPlayer);
  } catch (e) {
    debugPrint('Failed to shuffle music: $e');
  }
}
