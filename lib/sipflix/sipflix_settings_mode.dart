import 'package:get_it/get_it.dart';

import '../preference/user_preferences.dart';

/// Sipflix: Basic / Advanced settings.
///
/// Customers see a short Basic list by default. The Advanced mode switch at
/// the bottom of the main Settings page shows everything else.
///
/// A third group is hidden in both modes: settings that do nothing on Sipflix
/// (games, the Moonbase plugin and everything behind it, upstream Moonfin
/// links, multi-server options). They stay in the code behind [showRetired]
/// so bringing one back is a one-line change.
class SipflixSettingsMode {
  SipflixSettingsMode._();

  /// Flip to true to bring every retired setting back.
  static const bool showRetired = false;

  static bool get advanced {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<UserPreferences>()) return false;
    return getIt<UserPreferences>().get(
      UserPreferences.sipflixAdvancedSettings,
    );
  }

  static bool get basic => !advanced;

  /// Plain wording for Basic mode, so a label never names a hidden setting.
  static String label(String full, String basic) => advanced ? full : basic;
}
