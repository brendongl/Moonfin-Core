import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../data/models/aggregated_item.dart';
import '../util/download_utils.dart';
import 'sipflix_4k_policy.dart';

/// Casting bypasses PlaybackManager, so prepare and verify its sources too.
Future<({AggregatedItem item, String? sourceId})> prepareSipflixCastSource(
  MediaServerClient client,
  AggregatedItem item,
  String? sourceId,
) async {
  if (!Sipflix4kPolicy.prefersSmallest(item.serverId)) {
    return (item: item, sourceId: sourceId);
  }
  if (item.mediaSources.isEmpty) {
    final raw = await client.itemsApi
        .getItem(item.id)
        .timeout(const Duration(seconds: 20));
    item = AggregatedItem(id: item.id, serverId: item.serverId, rawData: raw);
  }
  final prepared = withPreferredMediaSource(item, sourceId);
  return (
    item: prepared,
    sourceId: prepared.mediaSources.firstOrNull?['Id']?.toString() ?? sourceId,
  );
}

Future<void> verifySipflixCastResolution(
  MediaServerClient client,
  AggregatedItem item,
  StreamResolutionResult resolution,
) async {
  final refusal = Sipflix4kPolicy.sourceRefusal(
    item,
    resolution.mediaStreams,
    resolution.mediaSourceId,
    // The receiver decodes the stream, not this controller's Allwinner chip.
    // Server-wide Delta restrictions still apply independently of this flag.
    fragileDecoder: false,
  );
  if (refusal == null) return;
  try {
    if (resolution.playSessionId != null) {
      await client.playbackApi
          .stopActiveEncodings(
            deviceId: client.deviceInfo.id,
            playSessionId: resolution.playSessionId,
          )
          .timeout(const Duration(seconds: 5));
    }
    if (resolution.liveStreamId != null) {
      await client.playbackApi
          .closeLiveStream(resolution.liveStreamId!)
          .timeout(const Duration(seconds: 5));
    }
  } catch (_) {}
  throw StateError(refusal);
}
