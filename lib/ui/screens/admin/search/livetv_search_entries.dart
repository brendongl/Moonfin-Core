import '../admin_search_index.dart';

/// Search entries for the Live TV page. Each anchor matches an
/// AdminSettingAnchor id on the page.
final List<AdminSearchEntry> livetvSearchEntries = [
  adminSettingRow('live-tv', 'TunerHosts', (l) => l.adminTunerDevices,
      (l) => l.adminLiveTvTabSources),
  adminSettingRow('live-tv', 'ListingProviders', (l) => l.adminGuideProviders,
      (l) => l.adminLiveTvTabSources),
  adminSettingRow('live-tv', 'GuideDays', (l) => l.adminLiveTvGuideDays,
      (l) => l.adminLiveTvSectionGuide),
  adminSettingRow('live-tv', 'WakeServer', (l) => l.adminLiveTvWakeServer,
      (l) => l.adminLiveTvSectionGuide, servers: embyOnly),
  adminSettingRow('live-tv', 'RecordingPath', (l) => l.adminLiveTvRecordingPath,
      (l) => l.adminLiveTvSectionPaths),
  adminSettingRow('live-tv', 'MovieRecordingPath', (l) => l.adminMovieRecordingPath,
      (l) => l.adminLiveTvSectionPaths),
  adminSettingRow('live-tv', 'SeriesRecordingPath', (l) => l.adminSeriesRecordingPath,
      (l) => l.adminLiveTvSectionPaths),
  adminSettingRow('live-tv', 'PrePaddingSeconds', (l) => l.adminLiveTvStartWhenPossible,
      (l) => l.adminLiveTvSectionDefaultRecording),
  adminSettingRow('live-tv', 'PostPaddingSeconds', (l) => l.adminLiveTvStopWhenPossible,
      (l) => l.adminLiveTvSectionDefaultRecording),
  adminSettingRow('live-tv', 'RecordingPostProcessor',
      (l) => l.adminRecordingPostProcessor,
      (l) => l.adminLiveTvSectionPostProcessing),
  adminSettingRow('live-tv', 'RecordingPostProcessorArguments',
      (l) => l.adminRecordingPostProcessorArgs,
      (l) => l.adminLiveTvSectionPostProcessing),
  adminSettingRow('live-tv', 'SaveRecordingNFO', (l) => l.adminSaveRecordingNfo,
      (l) => l.adminLiveTvSectionMetadata, servers: jellyfinOnly),
  adminSettingRow('live-tv', 'SaveRecordingImages', (l) => l.adminSaveRecordingImages,
      (l) => l.adminLiveTvSectionMetadata, servers: jellyfinOnly),
];
