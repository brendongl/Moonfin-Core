import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import 'sipflix_servers.dart';

const sipflixErrorReportUrl = String.fromEnvironment(
  'SIPFLIX_ERROR_REPORT_URL',
);
typedef SipflixErrorPost = Future<void> Function(Map<String, dynamic> event);

/// Bounded, best-effort diagnostics. No disk queue, tokens, passwords, response
/// bodies, retries or recursive logging. Reporting never blocks playback/login.
class SipflixErrorReporter {
  SipflixErrorReporter({
    required this.post,
    required this.metadata,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SipflixErrorPost post;
  final Future<Map<String, String>> Function() metadata;
  final DateTime Function() _now;
  final Map<String, DateTime> _recent = {};
  DateTime? _window;
  int _count = 0;
  int _pending = 0;
  static SipflixErrorReporter? _live;

  static SipflixErrorReporter? get live {
    final uri = Uri.tryParse(sipflixErrorReportUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return _live ??= SipflixErrorReporter(
      metadata: _deviceMetadata,
      post: (event) async {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            followRedirects: false,
          ),
        );
        try {
          await dio.post<void>(sipflixErrorReportUrl, data: event);
        } finally {
          dio.close(force: true);
        }
      },
    );
  }

  static Future<String?>? _androidId;
  static Future<Map<String, String>> _deviceMetadata() async {
    final getIt = GetIt.instance;
    final device = getIt.isRegistered<DeviceInfo>()
        ? getIt<DeviceInfo>()
        : null;
    _androidId ??= const MethodChannel('org.moonfin.androidtv/platform')
        .invokeMethod<String>('sipflixAndroidId')
        .timeout(const Duration(seconds: 2))
        .catchError((Object _) => null);
    return {
      'deviceName': device?.name ?? 'unknown',
      'androidId': await _androidId ?? 'unavailable',
      'appVersion': device?.appVersion ?? 'unknown',
    };
  }

  static String redact(String text) {
    // Bound work before applying patterns. Header values must be removed before
    // key/value matching, which alone would consume "Bearer" and leak its token.
    var safe = text.length > 16384 ? text.substring(0, 16384) : text;
    safe = safe.replaceAll(
      RegExp(r'https?://[^\s<>]+', caseSensitive: false),
      '[url]',
    );
    safe = safe.replaceAll(
      RegExp(
        r"\b(?:authorization|cookie|set-cookie|x-emby-token|x-mediabrowser-token)\s*:\s*[^\r\n]+",
        caseSensitive: false,
      ),
      '[authorization removed]',
    );
    safe = safe.replaceAll(
      RegExp(
        r'\b(?:Bearer|Basic|MediaBrowser|Emby)\s+[^\r\n]+',
        caseSensitive: false,
      ),
      '[authorization removed]',
    );
    safe = safe.replaceAll(
      RegExp(
        r'''["']?(?:password|passwd|pwd|pw|access[_-]?token|api[_-]?key|x-emby-token|x-mediabrowser-token|authorization|cookie|set-cookie|token)["']?\s*[:=]\s*(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;&}]+)''',
        caseSensitive: false,
      ),
      '[credential removed]',
    );
    safe = safe.replaceAll(RegExp(r'\?[^\s<>]+'), '[query removed]');
    return safe.length > 1000 ? safe.substring(0, 1000) : safe;
  }

  static String _field(String value, int limit) {
    final safe = redact(value);
    return safe.length <= limit ? safe : safe.substring(0, limit);
  }

  static void capture(
    String category,
    Object error, {
    String? baseUrl,
    String? code,
  }) {
    final reporter = live;
    if (reporter == null) return;
    var server = 'not signed in';
    var route = 'unknown';
    try {
      final getIt = GetIt.instance;
      final url =
          baseUrl ??
          (getIt.isRegistered<MediaServerClient>()
              ? getIt<MediaServerClient>().baseUrl
              : null);
      final def = url == null ? null : SipflixServers.defForRef(url);
      if (def != null) {
        server = def.name;
        route =
            def.routes.where((r) => r.url == url).firstOrNull?.label ??
            'unknown';
      }
    } catch (_) {}
    // Dio's string includes raw request details; only send type and status.
    final message = error is DioException
        ? 'Request failed: ${error.type.name}'
        : redact(error.toString());
    final status =
        code ??
        (error is DioException
            ? error.response?.statusCode?.toString() ?? error.type.name
            : 'unknown');
    unawaited(
      reporter.report(
        category: category,
        message: message,
        code: status,
        server: server,
        route: route,
      ),
    );
  }

  Future<void> report({
    required String category,
    required String message,
    required String code,
    required String server,
    required String route,
  }) async {
    final now = _now();
    _recent.removeWhere(
      (_, at) => now.difference(at) >= const Duration(minutes: 1),
    );
    if (_window == null ||
        now.difference(_window!) >= const Duration(minutes: 1)) {
      _window = now;
      _count = 0;
    }
    final safeMessage = redact(message);
    final key =
        '${_field(category, 64)}|${_field(server, 128)}|${_field(route, 256)}|${_field(code, 64)}|$safeMessage';
    if (_pending >= 2 || _count >= 10 || _recent.containsKey(key)) return;
    _recent[key] = now;
    _count++;
    _pending++;
    try {
      final device = await metadata().timeout(const Duration(seconds: 2));
      await post({
        'deviceName': _field(device['deviceName'] ?? 'unknown', 128),
        'androidId': _field(device['androidId'] ?? 'unavailable', 128),
        'appVersion': _field(device['appVersion'] ?? 'unknown', 64),
        'category': _field(category, 64),
        'message': safeMessage,
        'code': _field(code, 64),
        'server': _field(server, 128),
        'route': _field(route, 256),
        'timestamp': now.toUtc().toIso8601String(),
      }).timeout(const Duration(seconds: 6));
    } catch (_) {
      // No claim of successful delivery; failed reports are not retried.
    } finally {
      _pending--;
    }
  }
}
