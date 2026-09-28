part of '../settings_side_panel.dart';

class _CustomizationCategoryScreen extends StatelessWidget {
  const _CustomizationCategoryScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final advanced = SipflixSettingsMode.advanced;
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(
          context,
          Text(l10n.settingsPersonalization),
        ),
        body: ListView(
          children: [
            _SectionHeader(l10n.appearance),
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  autofocus: true,
                  leading: const Icon(Icons.style),
                  title: Text(l10n.settingsGeneralStyle),
                  subtitle: Text(
                    SipflixSettingsMode.label(
                      l10n.settingsGeneralStyleSubtitle,
                      'Clock',
                    ),
                  ),
                  onTap: () =>
                      context.pushSettingsScreen(const _GeneralStyleScreen()),
                ),
                if (advanced)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(l10n.settingsDetailsScreen),
                    subtitle: Text(l10n.settingsDetailsScreenSubtitle),
                    onTap: () => context.pushSettingsScreen(
                      const _DetailsScreenSettingsScreen(),
                    ),
                  ),
                if (advanced)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.view_sidebar),
                    title: Text(l10n.navigation),
                    subtitle: Text(l10n.navbarStyleToolbarAppearance),
                    onTap: () => context.pushSettingsScreen(
                      const _NavigationCategoryScreen(),
                    ),
                  ),
                if (PlatformDetection.isTV)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.wallpaper),
                    title: Text(l10n.screensaver),
                    subtitle: Text(l10n.enableBuiltInScreensaver),
                    onTap: () => context.pushSettingsScreen(
                      const ScreensaverSettingsScreen(),
                    ),
                  ),
              ],
            ),
            _SectionHeader(l10n.layout),
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  leading: const Icon(Icons.home),
                  title: Text(l10n.homeScreen),
                  subtitle: Text(
                    SipflixSettingsMode.label(
                      l10n.settingsHomePageSubtitle,
                      'Choose which rows show on the home screen',
                    ),
                  ),
                  onTap: () => context.pushSettingsScreen(
                    const _HomeScreenCategoryScreen(),
                  ),
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.video_library),
                  title: Text(l10n.libraries),
                  subtitle: Text(
                    SipflixSettingsMode.label(
                      l10n.settingsLibrariesSubtitle,
                      'Choose which libraries show',
                    ),
                  ),
                  onTap: () => context.pushSettingsScreen(
                    const _LibrariesCategoryScreen(),
                  ),
                ),
              ],
            ),
            _SectionHeader(l10n.extras),
            adaptiveListSection(
              children: [
                if (advanced)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.featured_play_list),
                    title: Text(l10n.mediaBar),
                    subtitle: Text(l10n.featuredContentAppearance),
                    onTap: () => context.pushSettingsScreen(
                      const MediaBarSettingsScreen(),
                    ),
                  ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.preview),
                  title: Text(l10n.localPreviews),
                  subtitle: Text(l10n.localPreviewsDescription),
                  onTap: () => context.pushSettingsScreen(
                    const LocalPreviewsSettingsScreen(),
                  ),
                ),
                if (advanced)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: Text(l10n.seasonalEffects),
                    subtitle: Text(l10n.seasonalEffectsDescription),
                    onTap: () => context.pushSettingsScreen(
                      const _SeasonalEffectsScreen(),
                    ),
                  ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(l10n.themeMusic),
                  subtitle: Text(l10n.themeMusicSettingsSubtitle),
                  onTap: () =>
                      context.pushSettingsScreen(const _ThemeMusicScreen()),
                ),
                // Sipflix: moved here from the hidden Integrations category.
                if (advanced && !SipflixSettingsMode.showRetired)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Ratings'),
                    subtitle: const Text('How the star rating looks'),
                    onTap: () => context.pushSettingsScreen(
                      const _MetadataRatingsScreen(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _pushPersonalizationSync() {
  final syncService = GetIt.instance<PluginSyncService>();
  if (syncService.pluginAvailable) {
    syncService.pushSettings(GetIt.instance<MediaServerClient>());
  }
}
