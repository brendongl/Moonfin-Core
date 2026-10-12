part of '../settings_side_panel.dart';

class _PlaybackCategoryScreen extends StatelessWidget {
  const _PlaybackCategoryScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final advanced = SipflixSettingsMode.advanced;
    // Sipflix: no game libraries, so the game settings stay hidden.
    const games = SipflixSettingsMode.showRetired;
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(
          context,
          Text(
            SipflixSettingsMode.label(
              l10n.settingsPlaybackSyncplay,
              l10n.playback,
            ),
          ),
        ),
        // Rebuild on preference changes so the Emulator Cores tile appears or
        // disappears the moment the emulator backend toggle flips.
        body: ListenableBuilder(
          listenable: GetIt.instance<UserPreferences>(),
          builder: (context, _) => ListView(
            children: [
              _SectionHeader(l10n.playback),
              adaptiveListSection(
                children: [
                  _TvSettingsListTile(
                    autofocus: true,
                    leading: const Icon(Icons.play_circle),
                    title: Text(l10n.settingsVideoPlaybackPreferences),
                    subtitle: Text(
                      SipflixSettingsMode.label(
                        l10n.settingsVideoPlaybackPreferencesSubtitle,
                        'Picture zoom',
                      ),
                    ),
                    onTap: () => context.pushSettingsScreen(
                      const _VideoPlaybackScreen(),
                    ),
                  ),
                  _TvSettingsListTile(
                    leading: const Icon(Icons.volume_up),
                    title: Text(l10n.settingsAudioPreferences),
                    subtitle: Text(
                      SipflixSettingsMode.label(
                        l10n.settingsAudioPreferencesSubtitle,
                        'Audio language and night mode',
                      ),
                    ),
                    onTap: () => context.pushSettingsScreen(
                      const _AudioPreferencesScreen(),
                    ),
                  ),
                  _TvSettingsListTile(
                    leading: const Icon(Icons.subtitles),
                    title: Text(l10n.subtitlePreferences),
                    subtitle: Text(
                      SipflixSettingsMode.label(
                        l10n.subtitlePreferencesDescription,
                        'Subtitle language, mode and size',
                      ),
                    ),
                    onTap: () => context.pushSettingsScreen(
                      const SubtitleSettingsScreen(),
                    ),
                  ),
                ],
              ),
              _SectionHeader(l10n.general),
              adaptiveListSection(
                children: [
                  _TvSettingsListTile(
                    leading: const Icon(Icons.queue_play_next),
                    title: Text(l10n.settingsAutomationAndQueue),
                    subtitle: Text(l10n.settingsAutomationAndQueueSubtitle),
                    onTap: () => context.pushSettingsScreen(
                      const _AutomationQueueScreen(),
                    ),
                  ),
                  // Sipflix fork: offline downloads are retired on TV boxes.
                  if (PlatformDetection.supportsOfflineDownloads &&
                      !PlatformDetection.isWeb &&
                      (!PlatformDetection.isTV ||
                          SipflixSettingsMode.showRetired))
                    _TvSettingsListTile(
                      leading: const Icon(Icons.download_for_offline),
                      title: Text(l10n.settingsOfflineDownloads),
                      subtitle: Text(l10n.settingsOfflineDownloadsSubtitle),
                      onTap: () => context.pushSettingsScreen(
                        const DownloadSettingsScreen(),
                      ),
                    ),
                  if (games && canToggleGameBackend)
                    SwitchPreferenceTile(
                      preference: UserPreferences.useNativeEmulator,
                      title: l10n.useNativeEmulator,
                      subtitle: l10n.useNativeEmulatorSubtitle,
                      icon: Icons.sports_esports,
                    ),
                  if (games && supportsCoreDownloads && usesNativeGameBackend)
                    _TvSettingsListTile(
                      leading: const Icon(Icons.videogame_asset),
                      title: Text(l10n.emulatorCores),
                      subtitle: Text(l10n.emulatorCoresSubtitle),
                      onTap: () => context.pushSettingsScreen(
                        const EmulatorCoresScreen(),
                      ),
                    ),
                  if (games && usesNativeGameBackend)
                    _TvSettingsListTile(
                      leading: const Icon(Icons.sd_storage),
                      title: Text(l10n.downloadedGames),
                      subtitle: Text(l10n.downloadedGamesSubtitle),
                      onTap: () => context.pushSettingsScreen(
                        const DownloadedGamesScreen(),
                      ),
                    ),
                  if (advanced)
                    _TvSettingsListTile(
                      leading: const Icon(Icons.groups),
                      title: Text(l10n.syncPlay),
                      subtitle: Text(l10n.settingsSyncplaySubtitle),
                      onTap: () => context.pushSettingsScreen(
                        const _SyncPlaySettingsScreen(),
                      ),
                    ),
                  if (advanced)
                    _TvSettingsListTile(
                      leading: const Icon(Icons.settings),
                      title: Text(l10n.advancedOptions),
                      subtitle: Text(l10n.settingsAdvancedOptionsSubtitle),
                      onTap: () => context.pushSettingsScreen(
                        const _AdvancedOptionsScreen(),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
