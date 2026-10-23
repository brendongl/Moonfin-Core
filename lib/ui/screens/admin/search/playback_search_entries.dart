import '../../../../l10n/app_localizations.dart';
import '../admin_search_index.dart';

typedef _L = String Function(AppLocalizations l10n);

AdminSearchEntry _hw(String key, _L label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminPlaybackHwAccel);
AdminSearchEntry _hwEnc(String key, _L label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminPlaybackHwEncodingSection);
AdminSearchEntry _enc(String key, _L label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminPlaybackEncoding);
AdminSearchEntry _tone(String key, _L label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminPlaybackToneMapping);
AdminSearchEntry _audio(String key, _L label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminPlaybackAudioSection);
AdminSearchEntry _paths(String key, _L label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminGeneralSectionPaths);
AdminSearchEntry _segments(String key, _L label) =>
    adminSettingRow('transcoding', key, label, (l) => l.adminPlaybackStreaming);
AdminSearchEntry _trick(String key, _L label, _L section) =>
    adminSettingRow('trickplay', key, label, section);

/// Search entries for the playback pages. Each anchor matches an
/// AdminSettingAnchor id on the page. Some transcoding rows only show for
/// certain hardware types, and the search waits until they appear.
final List<AdminSearchEntry> playbackSearchEntries = [
  // Transcoding.
  _hw('HardwareAccelerationType', (l) => l.adminPlaybackHwAccelLabel),
  _hw('VaapiDevice', (l) => l.adminPlaybackVaapiDevice),
  _hw('QsvDevice', (l) => l.adminPlaybackQsvDevice),
  _hw('HardwareDecodingCodecs', (l) => l.adminTranscodingDecodingFor),
  _hw('EnableDecodingColorDepth10Hevc', (l) => l.adminPlaybackColorDepth10Hevc),
  _hw('EnableDecodingColorDepth10Vp9', (l) => l.adminPlaybackColorDepth10Vp9),
  _hw('EnableDecodingColorDepth10HevcRext',
      (l) => l.adminPlaybackColorDepth10HevcRext),
  _hw('EnableDecodingColorDepth12HevcRext',
      (l) => l.adminPlaybackColorDepth12HevcRext),
  _hw('EnableEnhancedNvdecDecoder', (l) => l.adminPlaybackEnhancedNvdec),
  _hw('PreferSystemNativeHwDecoder',
      (l) => l.adminPlaybackPreferNativeDecoder),
  _hwEnc('EnableHardwareEncoding', (l) => l.adminPlaybackEnableHwEncoding),
  _hwEnc('EnableIntelLowPowerH264HwEncoder',
      (l) => l.adminPlaybackIntelLowPowerH264),
  _hwEnc('EnableIntelLowPowerHevcHwEncoder',
      (l) => l.adminPlaybackIntelLowPowerHevc),
  _enc('AllowHevcEncoding', (l) => l.adminPlaybackAllowHevcEncoding),
  _enc('AllowAv1Encoding', (l) => l.adminPlaybackAllowAv1Encoding),
  _enc('EncoderPreset', (l) => l.adminPlaybackEncoderPreset),
  _enc('H265Crf', (l) => l.adminPlaybackH265Crf),
  _enc('H264Crf', (l) => l.adminPlaybackH264Crf),
  _enc('EncodingThreadCount', (l) => l.adminPlaybackEncodingThreads),
  _enc('DeinterlaceMethod', (l) => l.adminPlaybackDeinterlaceMethod),
  _enc('DeinterlaceDoubleRate', (l) => l.adminPlaybackDeinterlaceDoubleRate),
  _tone('EnableVppTonemapping', (l) => l.adminPlaybackEnableVppTonemapping),
  _tone('VppTonemappingBrightness',
      (l) => l.adminPlaybackVppTonemappingBrightness),
  _tone('VppTonemappingContrast', (l) => l.adminPlaybackVppTonemappingContrast),
  _tone('EnableVideoToolboxTonemapping',
      (l) => l.adminPlaybackEnableVtTonemapping),
  _tone('EnableTonemapping', (l) => l.adminPlaybackEnableTonemapping),
  _tone('TonemappingAlgorithm', (l) => l.adminPlaybackTonemappingAlgorithm),
  _tone('TonemappingMode', (l) => l.adminPlaybackTonemappingMode),
  _tone('TonemappingRange', (l) => l.adminPlaybackTonemappingRange),
  _tone('TonemappingDesat', (l) => l.adminPlaybackTonemappingDesat),
  _tone('TonemappingPeak', (l) => l.adminPlaybackTonemappingPeak),
  _tone('TonemappingParam', (l) => l.adminPlaybackTonemappingParam),
  _audio('EnableAudioVbr', (l) => l.adminPlaybackEnableAudioVbr),
  _audio('DownMixAudioBoost', (l) => l.adminPlaybackDownmixBoost),
  _audio('DownMixStereoAlgorithm', (l) => l.adminPlaybackDownmixAlgorithm),
  _audio('HlsAudioSeekStrategy', (l) => l.adminTranscodingAudioSeek),
  _audio('MaxMuxingQueueSize', (l) => l.adminPlaybackMaxMuxingQueue),
  _paths('EncoderAppPathDisplay', (l) => l.adminTranscodingFfmpegPath),
  _paths('TranscodingTempPath', (l) => l.adminPlaybackTranscodeTempPath),
  _paths('FallbackFontPath', (l) => l.adminPlaybackFallbackFontPath),
  _paths('EnableFallbackFont', (l) => l.adminPlaybackFallbackFont),
  _segments('EnableSubtitleExtraction',
      (l) => l.adminPlaybackEnableSubtitleExtraction),
  _segments('EnableThrottling', (l) => l.adminPlaybackThrottleBuffering),
  _segments('EnableSegmentDeletion', (l) => l.adminPlaybackSegmentDeletion),
  _segments('ThrottleDelaySeconds', (l) => l.adminPlaybackThrottleDelay),
  _segments('SegmentKeepSeconds', (l) => l.adminPlaybackSegmentKeep),

  // Resume.
  adminSettingRow('resume', 'MinResumePct', (l) => l.adminMinResumePercentage,
      (l) => l.adminResumeVideo),
  adminSettingRow('resume', 'MaxResumePct', (l) => l.adminMaxResumePercentage,
      (l) => l.adminResumeVideo),
  adminSettingRow('resume', 'MinResumeDurationSeconds', (l) => l.adminMinResumeDuration,
      (l) => l.adminResumeVideo),
  adminSettingRow('resume', 'MinAudiobookResume',
      (l) => l.adminResumeMinAudiobookMinutes, (l) => l.adminResumeAudiobooks),
  adminSettingRow('resume', 'MaxAudiobookResume', (l) => l.adminResumeAudiobookRemaining,
      (l) => l.adminResumeAudiobooks),

  // Streaming.
  adminSettingRow('streaming', 'RemoteClientBitrateLimit',
      (l) => l.adminStreamingBitrateLimit, (l) => l.general),

  // Trickplay.
  _trick('EnableHwAcceleration', (l) => l.adminTrickplayHwAccel,
      (l) => l.general),
  _trick('EnableHwEncoding', (l) => l.adminTrickplayHwEncoding,
      (l) => l.general),
  _trick('EnableKeyFrameOnlyExtraction', (l) => l.adminTrickplayKeyFrameOnly,
      (l) => l.general),
  _trick('ScanBehavior', (l) => l.adminTrickplayScanBehavior,
      (l) => l.general),
  _trick('ProcessPriority', (l) => l.adminTrickplayProcessPriority,
      (l) => l.general),
  _trick('Interval', (l) => l.adminTrickplayInterval,
      (l) => l.adminTrickplayImageSettings),
  _trick('WidthResolutions', (l) => l.adminTrickplayWidthResolutions,
      (l) => l.adminTrickplayImageSettings),
  _trick('TileWidth', (l) => l.adminTrickplayTileWidth,
      (l) => l.adminTrickplayImageSettings),
  _trick('TileHeight', (l) => l.adminTrickplayTileHeight,
      (l) => l.adminTrickplayImageSettings),
  _trick('Qscale', (l) => l.adminTrickplayQScale,
      (l) => l.adminTrickplayQuality),
  _trick('JpegQuality', (l) => l.adminTrickplayJpegQuality,
      (l) => l.adminTrickplayQuality),
  _trick('ProcessThreads', (l) => l.adminTrickplayProcessThreads,
      (l) => l.adminTrickplayProcessing),
];
