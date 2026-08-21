import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../data/services/log_service.dart';

/// Sipflix: a logger that still speaks on a customer's box.
///
/// `Logger()` defaults to [DevelopmentFilter], which decides whether to log
/// inside an `assert` — and asserts are stripped from a release build, so the
/// filter always answers "no". Every Sipflix log line (OTA, preflight, the
/// bandwidth probe) was therefore silent on the fleet, which is exactly where
/// the interesting failures happen: a 2026-08-21 investigation into a bogus
/// "1.3 Mbps" preflight reading had no instrumentation to read at all.
///
/// [ProductionFilter] applies the level in both modes.
Logger sipflixLogger({Level level = Level.info, LogOutput? output}) =>
    Logger(filter: ProductionFilter(), level: level, output: output);

/// Mirror a Sipflix diagnostic into the in-app log (Settings > Diagnostics), so
/// it can be read on the box itself rather than only over adb. No-op until the
/// service is registered, and cheap when the user has logging switched off.
void sipflixDiag(
  String message, {
  LogLevel level = LogLevel.info,
  LogCategory category = LogCategory.network,
}) {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<LogService>()) return;
  getIt<LogService>().log(category, message, level: level);
}
