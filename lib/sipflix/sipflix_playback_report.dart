import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// No credential or diagnostic URL is embedded in the APK. The endpoint is
/// pinned at build time; the viewer's Emby token travels only in an HTTPS header.
const sipflixPlaybackReportUrl = String.fromEnvironment(
  'SIPFLIX_PLAYBACK_REPORT_URL',
);

typedef PlaybackReportPost =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> event,
      String token,
      CancelToken cancel,
    );

class SipflixPlaybackReportResult {
  const SipflixPlaybackReportResult(
    this.diagnosis,
    this.reportStatus,
    this.issueId,
  );

  factory SipflixPlaybackReportResult.fromJson(Map<String, dynamic> json) {
    final issue = json['issueId'];
    final validIssue = issue is int && issue > 0 ? issue : null;
    var status = json['reportStatus']?.toString() ?? 'unavailable';
    // A malformed/partial response can never claim we reported anything.
    if ((status == 'reported' || status == 'replacement_requested') &&
        validIssue == null) {
      status = 'uncertain';
    }
    return SipflixPlaybackReportResult(
      json['diagnosis']?.toString() ?? 'unknown',
      status,
      validIssue,
    );
  }

  final String diagnosis;
  final String reportStatus;
  final int? issueId;
  bool get isMissing => diagnosis == 'missing';
  bool get pending => diagnosis == 'checking' && reportStatus == 'pending';
  bool get reported =>
      reportStatus == 'reported' || reportStatus == 'replacement_requested';

  String get title => isMissing
      ? 'The video file is missing on our server'
      : 'Playback could not start';

  String get message {
    if (isMissing && reported) {
      final action = reportStatus == 'replacement_requested'
          ? 'A replacement has been requested.'
          : 'The issue has been reported.';
      return '$action You don’t need to message support about this issue. '
          'You can watch something else while it is resolved. Report #$issueId.';
    }
    if (isMissing) {
      return 'We confirmed a problem with our copy, but could not confirm an '
          'automatic report. Please report this title at request.sipflix.net '
          'or contact support.';
    }
    if (diagnosis == 'access_denied') {
      return 'We couldn’t verify your playback access. Sign in again or contact support.';
    }
    if (diagnosis == 'source_readable') {
      return 'The video file is available, but playback failed. '
          'Try again or change connection.';
    }
    return 'We couldn’t confirm why playback failed or whether it was reported. '
        'Try again, or report this title at request.sipflix.net.';
  }
}

/// One bounded request per failed playback attempt. Late responses cannot
/// replace a new episode's screen. No passwords, durable token cache or logs.
class SipflixPlaybackReportController extends ChangeNotifier {
  SipflixPlaybackReportController({String? endpoint, PlaybackReportPost? post})
    : _endpoint = endpoint ?? sipflixPlaybackReportUrl,
      _postOverride = post;

  final String _endpoint;
  final PlaybackReportPost? _postOverride;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 40),
      followRedirects: false,
    ),
  );
  CancelToken? _cancel;
  String? _key;
  int _generation = 0;
  bool _disposed = false;
  bool checking = false;
  SipflixPlaybackReportResult? result;

  bool get enabled {
    final uri = Uri.tryParse(_endpoint);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> event,
    String token,
    CancelToken cancel,
  ) async {
    if (_postOverride != null) return _postOverride(event, token, cancel);
    final response = await _dio.post<Map<String, dynamic>>(
      _endpoint,
      data: event,
      cancelToken: cancel,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data ?? const {};
  }

  Future<void> check({
    required String failureKey,
    required String token,
    required String userId,
    required String itemId,
    required String mediaSourceId,
    required String playMethod,
    required int httpStatus,
    required String appVersion,
    String server = 'alphav2',
  }) async {
    if (!enabled || _disposed || _key == failureKey) return;
    reset();
    _key = failureKey;
    final generation = _generation;
    final cancel = _cancel = CancelToken();
    checking = true;
    notifyListeners();
    final event = <String, dynamic>{
      'server': server,
      'userId': userId,
      'itemId': itemId,
      'mediaSourceId': mediaSourceId,
      'attemptId': const Uuid().v4(),
      'playMethod': playMethod,
      'httpStatus': httpStatus,
      'appVersion': appVersion,
    };
    var value = const SipflixPlaybackReportResult(
      'unknown',
      'unavailable',
      null,
    );
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    try {
      // Only poll an explicit "already checking" response, never retry an
      // ambiguous POST timeout. Reuse attemptId for idempotency.
      for (var attempt = 0; attempt < 3; attempt++) {
        value = SipflixPlaybackReportResult.fromJson(
          await _post(
            event,
            token,
            cancel,
          ).timeout(deadline.difference(DateTime.now())),
        );
        if (!value.pending) break;
        if (attempt < 2) await Future<void>.delayed(const Duration(seconds: 2));
        if (generation != _generation || _disposed) return;
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        value = const SipflixPlaybackReportResult(
          'access_denied',
          'not_sent',
          null,
        );
      }
    } catch (_) {
      cancel.cancel();
      // Intentionally do not log DioException: it contains the auth header.
    }
    if (generation != _generation || _disposed) return;
    result = value;
    checking = false;
    notifyListeners();
  }

  void reset() {
    _generation++;
    _cancel?.cancel();
    _cancel = null;
    _key = null;
    checking = false;
    result = null;
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    _dio.close(force: true);
    super.dispose();
  }
}
