import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/system_ui.dart';

/// Wraps an index-driven game menu selection, including reverse navigation.
///
/// Game overlays intentionally do not use Flutter focus because their game
/// surface may be a platform view or a native texture. Both playback backends
/// therefore drive their menus with an integer selection.
int wrapGamePlaybackMenuSelection(int current, int delta, int itemCount) {
  if (itemCount <= 0) return 0;
  return ((current + delta) % itemCount + itemCount) % itemCount;
}

/// Scrolls an index-driven menu row into view without taking focus from the
/// active game surface.
void ensureGamePlaybackMenuSelectionVisible(
  ScrollController controller,
  int index, {
  required double rowExtent,
}) {
  if (!controller.hasClients) return;
  final position = controller.position;
  final top = index * rowExtent;
  final bottom = top + rowExtent;
  var target = position.pixels;
  if (top < position.pixels) {
    target = top;
  } else if (bottom > position.pixels + position.viewportDimension) {
    target = bottom - position.viewportDimension;
  }
  target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
  if (target == position.pixels) return;
  controller.animateTo(
    target,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
  );
}

/// Centers an index-driven menu row after returning from a nested editor.
void centerGamePlaybackMenuSelection(
  ScrollController controller,
  int index, {
  required double rowExtent,
}) {
  if (!controller.hasClients) return;
  final position = controller.position;
  final target = (index * rowExtent) -
      (position.viewportDimension - rowExtent) / 2;
  final clampedTarget = target
      .clamp(position.minScrollExtent, position.maxScrollExtent)
      .toDouble();
  if ((clampedTarget - position.pixels).abs() < 0.5) return;
  controller.animateTo(
    clampedTarget,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
  );
}

/// Displays a short non-blocking playback failure message.
void showGamePlaybackMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}

/// The orientations a game screen allows for a [GamePlaybackOrientation].
List<DeviceOrientation> deviceOrientationsFor(GamePlaybackOrientation o) =>
    switch (o) {
      GamePlaybackOrientation.landscape => const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      GamePlaybackOrientation.portrait => const [DeviceOrientation.portraitUp],
      GamePlaybackOrientation.auto => DeviceOrientation.values,
    };

/// The user's orientation choice. Landscape when preferences aren't wired up,
/// which is how the player widget tests build the screens.
GamePlaybackOrientation currentGamePlaybackOrientation() {
  if (!GetIt.instance.isRegistered<UserPreferences>()) {
    return GamePlaybackOrientation.landscape;
  }
  return GetIt.instance<UserPreferences>().get(
    UserPreferences.gamePlaybackOrientation,
  );
}

Future<void> saveGamePlaybackOrientation(GamePlaybackOrientation o) async {
  if (!GetIt.instance.isRegistered<UserPreferences>()) return;
  await GetIt.instance<UserPreferences>().set(
    UserPreferences.gamePlaybackOrientation,
    o,
  );
}

/// Steps to the next orientation choice, applies it to the device and saves
/// it. Returns the new choice for the caller's state.
GamePlaybackOrientation cycleGamePlaybackOrientation(
  GamePlaybackOrientation current,
) {
  const values = GamePlaybackOrientation.values;
  final next = values[(current.index + 1) % values.length];
  GamePlaybackSystemUi.apply(deviceOrientationsFor(next));
  unawaited(saveGamePlaybackOrientation(next));
  return next;
}

/// Label for an orientation choice. English when no localizations are at hand,
/// as in the native player's context-free menu list.
String gamePlaybackOrientationLabel(
  GamePlaybackOrientation o,
  AppLocalizations? l10n,
) => switch (o) {
  GamePlaybackOrientation.landscape => l10n?.landscape ?? 'Landscape',
  GamePlaybackOrientation.portrait => l10n?.portrait ?? 'Portrait',
  GamePlaybackOrientation.auto => l10n?.auto ?? 'Auto',
};

/// Shared full-screen system UI lifecycle for game players.
///
/// The flags preserve each backend's platform policy: EmulatorJS hides system
/// UI on every host while native playback does so only with touch controls.
/// A null [orientations] leaves the device alone (TV and desktop).
abstract final class GamePlaybackSystemUi {
  static void enter(
    ImmersiveSystemUi screen, {
    required bool immersive,
    List<DeviceOrientation>? orientations,
  }) {
    if (!immersive) return;
    screen.setImmersive(true);
    if (orientations != null) apply(orientations);
  }

  /// Re-applies an orientation choice mid-game, for the in-game menu row.
  static void apply(List<DeviceOrientation> orientations) =>
      SystemChrome.setPreferredOrientations(orientations);

  static Future<void> restore(
    ImmersiveSystemUi screen, {
    required bool immersive,
  }) async {
    if (!immersive) return;
    screen.setImmersive(false);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}
