import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Sipflix OTA: checks the fleet manifest on the VN VPS and walks the customer
/// through download -> verify -> install. Replaces the upstream GitHub updater,
/// which would offer upstream's builds, not the fork's.
///
/// Server layout (same pattern as the tvsupport agent OTA):
///   /var/www/html/moonfin/manifest.json
///   /var/www/html/moonfin/moonfin-tv-`<version>`-`<sha12>`.apk
///
/// The manifest's versionCode is compared against this build's own versionCode
/// (pubspec `sipflix_tv_build_number`, wired through build.gradle.kts), so every
/// published build MUST bump that number or the fleet never sees it.
class SipflixOtaUpdater {
  SipflixOtaUpdater({Dio? dio, Logger? logger})
      : _dio = dio ?? Dio(),
        _logger = logger ?? Logger();

  static const String manifestUrl =
      'http://103.98.148.133/moonfin/manifest.json';

  /// Startup checks honour this cooldown so a box that reboots in a loop is not
  /// hammering the VPS. A manual "Check for updates" bypasses it.
  static const Duration checkCooldown = Duration(hours: 6);

  static const _channel = MethodChannel('org.moonfin.androidtv/platform');

  final Dio _dio;
  final Logger _logger;

  DateTime? _lastCheckAt;
  bool _busy = false;

  /// Fetch the manifest and return the update when it is newer than this
  /// build; null means up to date or check failed (never throws).
  Future<SipflixOtaUpdate?> check({bool force = false}) async {
    if (_busy) return null;
    final now = DateTime.now();
    if (!force &&
        _lastCheckAt != null &&
        now.difference(_lastCheckAt!) < checkCooldown) {
      return null;
    }
    _lastCheckAt = now;
    try {
      final response = await _dio.get<String>(
        manifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final update = SipflixOtaUpdate(
        versionCode: (json['versionCode'] as num).toInt(),
        versionName: json['versionName']?.toString() ?? '',
        url: json['url'] as String,
        sha256: (json['sha256'] as String).toLowerCase(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        notes: json['notes']?.toString() ?? '',
      );
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;
      if (update.versionCode <= installed) return null;
      _logger.i('Sipflix OTA: ${update.versionName} '
          '(${update.versionCode}) available over $installed');
      return update;
    } catch (e) {
      _logger.d('Sipflix OTA check failed: $e');
      return null;
    }
  }

  /// Download the APK into cacheDir/ota, verify its sha256, and hand it to the
  /// system installer. Progress (0..1) is reported via [onProgress].
  /// Returns a user-displayable error, or null on success (the installer UI is
  /// in front of the app at that point).
  Future<String?> downloadAndInstall(
    SipflixOtaUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    if (_busy) return 'An update is already in progress';
    _busy = true;
    try {
      final cacheDir = await getTemporaryDirectory();
      final otaDir = Directory('${cacheDir.path}/ota');
      if (!await otaDir.exists()) await otaDir.create(recursive: true);
      final file = File('${otaDir.path}/moonfin-update.apk');
      if (await file.exists()) await file.delete();

      await _dio.download(
        update.url,
        file.path,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (received, total) {
          final denominator = total > 0 ? total : update.size;
          if (denominator > 0) onProgress?.call(received / denominator);
        },
      );

      // Never hand a mismatched file to the installer: a truncated or tampered
      // download must fail HERE, with a message, not as a cryptic parse error.
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != update.sha256) {
        await file.delete();
        return 'Download failed verification — please try again';
      }

      final outcome =
          await _channel.invokeMethod<String>('installApk', {'path': file.path});
      if (outcome == 'needs-permission') {
        return 'Allow installs from Sipflix Moonfin in the screen that just '
            'opened, then try the update again';
      }
      return null;
    } catch (e) {
      _logger.w('Sipflix OTA install failed: $e');
      return 'Update failed to download — check the connection and try again';
    } finally {
      _busy = false;
    }
  }
}

class SipflixOtaUpdate {
  final int versionCode;
  final String versionName;
  final String url;
  final String sha256;
  final int size;
  final String notes;

  const SipflixOtaUpdate({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
  });
}

/// TV-friendly update dialog: version + notes, one focused "Update now" button,
/// live progress while downloading. Barrier-dismissable so a customer can
/// always back out and keep watching.
Future<void> showSipflixOtaDialog(
  BuildContext context,
  SipflixOtaUpdater updater,
  SipflixOtaUpdate update,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _SipflixOtaDialog(updater: updater, update: update),
  );
}

class _SipflixOtaDialog extends StatefulWidget {
  final SipflixOtaUpdater updater;
  final SipflixOtaUpdate update;

  const _SipflixOtaDialog({required this.updater, required this.update});

  @override
  State<_SipflixOtaDialog> createState() => _SipflixOtaDialogState();
}

class _SipflixOtaDialogState extends State<_SipflixOtaDialog> {
  double? _progress;
  String? _error;

  bool get _downloading => _progress != null && _error == null;

  Future<void> _start() async {
    // TV remotes double-activate buttons (key action + tap semantics); the
    // second call must not clobber the live progress with a busy error.
    if (_downloading) return;
    setState(() {
      _error = null;
      _progress = 0;
    });
    final error = await widget.updater.downloadAndInstall(
      widget.update,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _error = error;
        _progress = null;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    return AlertDialog(
      title: Text('Update available — ${update.versionName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (update.notes.isNotEmpty) Text(update.notes),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('Downloading… ${((_progress ?? 0) * 100).round()}%'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: _downloading ? null : _start,
          child: Text(_error != null ? 'Try again' : 'Update now'),
        ),
      ],
    );
  }
}

/// Zero-size widget mounted in the app shell: shortly after the UI settles it
/// runs the cooldown-gated OTA check and, when an update exists, shows the
/// dialog on the root navigator. Lives in the shell so it works no matter which
/// screen the box lands on after boot.
class SipflixOtaGate extends StatefulWidget {
  /// Resolves the context dialogs should open on (the root navigator's).
  final BuildContext Function() navigatorContext;

  const SipflixOtaGate({super.key, required this.navigatorContext});

  @override
  State<SipflixOtaGate> createState() => _SipflixOtaGateState();
}

class _SipflixOtaGateState extends State<SipflixOtaGate> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Late enough that login/home bring-up wins the race for the first frames.
    _timer = Timer(const Duration(seconds: 20), _run);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final updater = GetIt.instance<SipflixOtaUpdater>();
    final update = await updater.check();
    if (update == null || !mounted) return;
    final context = widget.navigatorContext();
    if (!context.mounted) return;
    await showSipflixOtaDialog(context, updater, update);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
