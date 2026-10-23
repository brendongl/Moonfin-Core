import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import 'immersive_music_screen.dart';
import 'music_browse_screen.dart';
import 'quick_access_music_screen.dart';

/// A music library in the style picked in Settings, swapped as soon as the
/// setting changes.
class MusicLibraryScreen extends StatelessWidget {
  final String libraryId;

  const MusicLibraryScreen({super.key, required this.libraryId});

  @override
  Widget build(BuildContext context) {
    final prefs = GetIt.instance<UserPreferences>();
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) =>
          switch (prefs.get(UserPreferences.musicLibraryStyle)) {
            MusicLibraryStyle.classic => MusicBrowseScreen(libraryId: libraryId),
            MusicLibraryStyle.quickAccess => QuickAccessMusicScreen(
              libraryId: libraryId,
            ),
            MusicLibraryStyle.immersive => ImmersiveMusicScreen(
              libraryId: libraryId,
            ),
          },
    );
  }
}
