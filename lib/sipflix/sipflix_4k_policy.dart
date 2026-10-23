import '../util/platform_detection.dart';
import 'sipflix_servers.dart';

/// Sipflix: which boxes may be handed HEVC/4K, and which sources may only
/// ever direct play.
///
/// The fleet's Allwinner boxes (H6/H313/H616/H618, `apollo` platform) crash
/// their `libOmxVdec` decoder on HEVC, so they stay on H.264. Everything else
/// (Shield, Amlogic, ...) advertises what its decoders report.
///
/// 4K is never transcoded: the provider stops 4K transcodes server-side, and a
/// 4K encode would starve the transcoder for everyone else anyway.
class Sipflix4kPolicy {
  Sipflix4kPolicy._();

  static const _allwinnerSocs = {'h6', 'h313', 'h616', 'h618'};

  /// Whether this box's HEVC decoder is known to crash, so it must be sent
  /// H.264 only. Unknown hardware (capabilities not yet probed) counts as
  /// fragile: a needless transcode is recoverable, a frozen box is not.
  static bool get isFragileHevcDecoder {
    final hardware = (PlatformDetection.deviceHardware ?? '').toLowerCase();
    final board = (PlatformDetection.deviceBoard ?? '').toLowerCase();
    final soc = (PlatformDetection.deviceSocModel ?? '').toLowerCase();
    if (hardware.isEmpty && board.isEmpty && soc.isEmpty) return true;
    return isFragileHevcHardware(hardware: hardware, board: board, soc: soc);
  }

  static bool isFragileHevcHardware({
    required String hardware,
    required String board,
    required String soc,
  }) {
    final ids = [hardware, board, soc].map((s) => s.toLowerCase());
    return ids.any(
      (id) =>
          id.startsWith('sun') ||
          id.contains('allwinner') ||
          id == 'apollo' ||
          _allwinnerSocs.contains(id),
    );
  }

  /// Width at or above which a video counts as 4K. Scope-cropped UHD
  /// (3840x1600) is still 4K, so width decides, not height.
  static const int uhdMinWidth = 3200;

  static const String refusalMessage =
      'This is a 4K title and it can only play directly — 4K is never '
      'converted. This device or connection could not play it. Choose the '
      'HD version instead.';

  static const String unsupportedDeviceMessage =
      'This is a 4K title and this device can\'t play 4K. Choose the HD '
      'version instead.';

  /// Shown instead of [unsupportedDeviceMessage] when the title has no
  /// non-4K source at all — "choose the HD version instead" is impossible
  /// advice for a 4K-only title (R1-B finding: "Barreda" reachable via
  /// Search, dead-ending on advice the customer can't follow).
  static const String onlyAvailableIn4kMessage =
      'This title is only available in 4K, which this box can\'t play.';

  /// Whether [message] is one of this policy's deliberate refusals rather
  /// than a playback fault.
  static bool isRefusal(String? message) =>
      message == refusalMessage ||
      message == unsupportedDeviceMessage ||
      message == onlyAvailableIn4kMessage ||
      message == deltaHdOnlyMessage ||
      message == castQueueUnsupportedMessage;

  /// Whether [sources] (a title's full, unfiltered media sources) has at
  /// least one version this fragile-decoder box could actually play.
  static bool hasPlayableAlternative(List<Map<String, dynamic>> sources) =>
      sources.any((s) => !isUhdSource(s));

  /// The message to show when a fragile-decoder box can't play the
  /// requested source: the normal "choose the HD version instead" when one
  /// exists, or a plain "can't play this at all" message when the title is
  /// 4K-only and there is nothing else to choose.
  static String messageForUnsupportedDevice(
    List<Map<String, dynamic>>? sources,
  ) {
    if (sources != null &&
        sources.isNotEmpty &&
        !hasPlayableAlternative(sources)) {
      return onlyAvailableIn4kMessage;
    }
    return unsupportedDeviceMessage;
  }

  /// [PlaybackManager.directPlayOnlyUnavailable]: a box on H.264 only can't
  /// direct play 4K HEVC, and trying hands it to the decoder that crashes.
  /// [item] (duck-typed: anything with a `mediaSources` getter) lets the
  /// message say "this title is 4K-only" instead of the impossible-to-follow
  /// "choose the HD version instead" when no HD version exists at all.
  static String? unavailableOnThisDevice([dynamic item]) {
    if (!isFragileHevcDecoder) return null;
    List? rawSources;
    try {
      rawSources = item?.mediaSources as List?;
    } catch (_) {}
    final sources = rawSources
        ?.whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    return messageForUnsupportedDevice(sources);
  }

  /// [PlaybackManager.directPlayOnlyPolicy]: the refusal message for a 4K
  /// source, null for anything else.
  ///
  /// Only the version being played counts: a title merged from a 4K and an
  /// HD file must still let the HD one transcode.
  static String? directPlayOnly(
    dynamic item,
    List<Map<String, dynamic>> mediaStreams,
    String? mediaSourceId,
  ) {
    if (_hasUhdVideo(mediaStreams)) return refusalMessage;
    List? sources;
    try {
      sources = item.mediaSources as List?;
    } catch (_) {}
    final candidates = (sources ?? const []).whereType<Map>().toList();
    // A thin item with no media-source data at all (e.g. a list-row item
    // before its detail fetch) can't be judged here either way; the
    // post-resolve safety net below re-checks the server's own resolved
    // streams once they exist, so it still catches a real 4K source.
    if (candidates.isEmpty) return null;
    final Map source = mediaSourceId == null
        ? candidates.first
        : candidates.firstWhere(
            (s) => s['Id'] == mediaSourceId,
            orElse: () => const {},
          );
    if (source.isEmpty) {
      // mediaSourceId was supplied but matches none of this item's known
      // sources — a stale/drifted id, not proof the selected version is HD.
      return refusalMessage;
    }
    final streams = source['MediaStreams'];
    if (streams is List &&
        _hasUhdVideo(
          streams.whereType<Map>().map((m) => m.cast<String, dynamic>()),
        )) {
      return refusalMessage;
    }
    return null;
  }

  /// Whether a single media [source] carries a 4K video stream.
  static bool isUhdSource(Map source) {
    final streams = source['MediaStreams'];
    if (streams is! List) return false;
    return _hasUhdVideo(
      streams.whereType<Map>().map((m) => m.cast<String, dynamic>()),
    );
  }

  static const String castQueueUnsupportedMessage =
      'This remote player cannot keep the selected versions for a queue. '
      'Cast one title at a time.';

  static const String deltaHdOnlyMessage =
      'This version is above 1080p and is not available on Delta. '
      'Choose an HD version or another title.';

  static bool isDelta(String? serverRef) =>
      serverRef != null && SipflixServers.defForRef(serverRef)?.key == 'emby2';

  static bool prefersSmallest(String? serverRef) {
    if (serverRef == null) return false;
    final key = SipflixServers.defForRef(serverRef)?.key;
    return key == 'AlphaV2' || key == 'emby2';
  }

  static bool exceedsDeltaHd(Iterable<Map<String, dynamic>> streams) =>
      streams.any((stream) {
        if (stream['Type'] != 'Video') return false;
        final height = stream['Height'];
        final width = stream['Width'];
        return (height is num && height > 1080) ||
            (width is num && width >= uhdMinWidth);
      });

  static bool isAboveDeltaHdSource(Map source) {
    final height = source['Height'];
    final width = source['Width'];
    if ((height is num && height > 1080) ||
        (width is num && width >= uhdMinWidth)) {
      return true;
    }
    final streams = source['MediaStreams'];
    return streams is List &&
        exceedsDeltaHd(
          streams.whereType<Map>().map((m) => m.cast<String, dynamic>()),
        );
  }

  /// Strict server restriction, independent of device codec capabilities or
  /// whether a source could direct play. Resolved streams recheck thin items.
  static String? sourceRefusal(
    dynamic item,
    List<Map<String, dynamic>> streams,
    String? mediaSourceId,
  ) {
    String? serverRef;
    List<Map<String, dynamic>> sources = const [];
    try {
      serverRef = item.serverId as String?;
      sources = (item.mediaSources as List)
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
    } catch (_) {}
    if (!isDelta(serverRef)) return null;
    if (exceedsDeltaHd(streams)) return deltaHdOnlyMessage;
    if (sources.isEmpty) return null; // The resolver supplies the final check.
    if (selectableSources(sources, serverRef: serverRef).isEmpty) {
      return deltaHdOnlyMessage;
    }
    if (mediaSourceId != null) {
      final matches = sources.where(
        (s) => s['Id']?.toString() == mediaSourceId,
      );
      if (matches.isEmpty || isAboveDeltaHdSource(matches.first)) {
        return deltaHdOnlyMessage;
      }
    }
    return null;
  }

  /// Delta never offers a forbidden-only fallback. Other servers retain the
  /// fragile-device fallback so the existing explanatory refusal can show.
  static List<Map<String, dynamic>> selectableSources(
    List<Map<String, dynamic>> sources, {
    bool? cannotPlay4k,
    String? serverRef,
  }) {
    if (isDelta(serverRef)) {
      return sources.where((s) => !isAboveDeltaHdSource(s)).toList();
    }
    if (!(cannotPlay4k ?? isFragileHevcDecoder)) return sources;
    final hd = sources.where((s) => !isUhdSource(s)).toList();
    return hd.isEmpty ? sources : hd;
  }

  /// Alpha and Delta default to the smallest eligible file on every device.
  /// A manual eligible choice is retained by callers. Missing/nonfinite sizes
  /// lose to known positive sizes; ties retain server order.
  static Map<String, dynamic>? defaultSource(
    List<Map<String, dynamic>> sources, {
    bool? cannotPlay4k,
    String? serverRef,
  }) {
    final options = selectableSources(
      sources,
      cannotPlay4k: cannotPlay4k,
      serverRef: serverRef,
    );
    if (options.isEmpty) return null;
    if (!prefersSmallest(serverRef) && identical(options, sources)) {
      return options.first;
    }
    Map<String, dynamic>? best;
    num bestSize = 0;
    for (final s in options) {
      final size = s['Size'];
      if (size is! num || !size.isFinite || size <= 0) continue;
      if (best == null || size < bestSize) {
        best = s;
        bestSize = size;
      }
    }
    return best ?? options.first;
  }

  static bool _hasUhdVideo(Iterable<Map<String, dynamic>> streams) {
    for (final stream in streams) {
      if (stream['Type'] != 'Video') continue;
      final width = stream['Width'];
      if (width is num && width >= uhdMinWidth) return true;
    }
    return false;
  }
}
