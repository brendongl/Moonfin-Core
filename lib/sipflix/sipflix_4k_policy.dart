import '../util/platform_detection.dart';

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
    return ids.any((id) =>
        id.startsWith('sun') ||
        id.contains('allwinner') ||
        id == 'apollo' ||
        _allwinnerSocs.contains(id));
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

  /// Whether [message] is one of this policy's deliberate refusals rather
  /// than a playback fault.
  static bool isRefusal(String? message) =>
      message == refusalMessage || message == unsupportedDeviceMessage;

  /// [PlaybackManager.directPlayOnlyUnavailable]: a box on H.264 only can't
  /// direct play 4K HEVC, and trying hands it to the decoder that crashes.
  static String? unavailableOnThisDevice() =>
      isFragileHevcDecoder ? unsupportedDeviceMessage : null;

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
    if (candidates.isEmpty) return null;
    final Map source = mediaSourceId == null
        ? candidates.first
        : candidates.firstWhere(
            (s) => s['Id'] == mediaSourceId,
            orElse: () => const {},
          );
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

  /// The versions this device should be offered. A box that can't play 4K
  /// never sees the 4K versions of a title, unless 4K is all there is, so the
  /// refusal message still explains why nothing plays.
  static List<Map<String, dynamic>> selectableSources(
    List<Map<String, dynamic>> sources, {
    bool? cannotPlay4k,
  }) {
    if (!(cannotPlay4k ?? isFragileHevcDecoder)) return sources;
    final hd = sources.where((s) => !isUhdSource(s)).toList();
    return hd.isEmpty ? sources : hd;
  }

  /// The version to start on when the viewer hasn't picked one: the widest
  /// non-4K version on a box that can't play 4K, else the server's first.
  static Map<String, dynamic>? defaultSource(
    List<Map<String, dynamic>> sources, {
    bool? cannotPlay4k,
  }) {
    if (sources.isEmpty) return null;
    final options = selectableSources(sources, cannotPlay4k: cannotPlay4k);
    if (identical(options, sources)) return sources.first;
    var best = options.first;
    var bestWidth = _sourceWidth(best);
    for (final s in options.skip(1)) {
      final w = _sourceWidth(s);
      if (w > bestWidth) {
        best = s;
        bestWidth = w;
      }
    }
    return best;
  }

  static num _sourceWidth(Map source) {
    final streams = source['MediaStreams'];
    if (streams is! List) return 0;
    for (final m in streams.whereType<Map>()) {
      if (m['Type'] == 'Video' && m['Width'] is num) return m['Width'] as num;
    }
    return 0;
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
