import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Short-lived relay pairing. Only the TV capability can consume credentials
/// and acknowledge a completed sign-in; the phone sees status only.
class SipflixPairingClient {
  static const configuredUrl = String.fromEnvironment('SIPFLIX_PAIRING_URL');
  final Uri base;
  final Future<String?> Function(String, String) onCredentials;
  final void Function(String) onStatus;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  Timer? _timer;
  String? _id;
  String? _tv;
  DateTime? _expires;
  bool _closing = false;
  bool _polling = false;
  bool _finished = false;

  SipflixPairingClient({
    required this.base,
    required this.onCredentials,
    required this.onStatus,
  });

  bool get isExpired => _expires != null && !DateTime.now().isBefore(_expires!);

  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic> data = const {},
  ]) async {
    final request = await _http
        .postUrl(base.resolve(path))
        .timeout(const Duration(seconds: 6));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (_tv != null) request.headers.set('Authorization', 'Bearer $_tv');
    request.write(jsonEncode(data));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 16384) {
        throw const FormatException('Pairing response too large');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Pairing request failed (${response.statusCode})');
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<String> start() async {
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty) {
      throw const FormatException('Pairing requires HTTPS');
    }
    final result = await _post('/v1/pair');
    final id = result['id'] as String;
    final phone = result['phone'] as String;
    final tv = result['tv'] as String;
    final valid = RegExp(r'^[A-Za-z0-9_-]{43}$');
    if (!valid.hasMatch(id) || !valid.hasMatch(phone) || !valid.hasMatch(tv)) {
      throw const FormatException('Invalid pairing response');
    }
    _id = id;
    _tv = tv;
    _expires = DateTime.now().add(
      Duration(seconds: (result['expiresIn'] as num).toInt().clamp(1, 300)),
    );
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_poll()),
    );
    return base.resolve('/pair').replace(fragment: '$id.$phone').toString();
  }

  Future<void> _poll() async {
    if (_closing || _polling || _finished) return;
    _polling = true;
    try {
      if (DateTime.now().isAfter(_expires!)) {
        onStatus('Phone sign-in expired. Go back and open a new QR code.');
        _closing = true;
        return;
      }
      final result = await _post('/v1/pair/$_id/tv/poll');
      if (_closing) return;
      if (['failed', 'cancelled', 'success'].contains(result['state'])) {
        onStatus('Phone sign-in ended. Go back and open a new QR code.');
        _closing = true;
        return;
      }
      final credentials = result['credentials'];
      if (credentials is Map<String, dynamic>) {
        String? error;
        try {
          error = await onCredentials(
            credentials['username'] as String,
            credentials['password'] as String,
          );
        } catch (_) {
          error = 'Sign-in failed. Open a new QR code to try again.';
        }
        // A successful callback can dispose the screen through navigation.
        // Complete this acknowledgement before cancelling the pairing session.
        await _post('/v1/pair/$_id/tv/ack', {
          'attempt': result['attempt'],
          'success': error == null,
        });
        _finished = true;
        _timer?.cancel();
        if (error != null) onStatus(error);
      }
    } catch (_) {
      onStatus(
        'Phone sign-in connection ended. Go back and open a new QR code.',
      );
      _closing = true;
    } finally {
      _polling = false;
      if (_closing) await _cancel();
    }
  }

  /// Stop accepting credentials immediately, but let an in-flight real sign-in
  /// report its outcome. User cancellation is an error from onCredentials.
  void closeAfterCurrent() {
    _closing = true;
    _timer?.cancel();
    if (!_polling) unawaited(_cancel());
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try {
      if (_id != null && !_finished) await _post('/v1/pair/$_id/tv/cancel');
    } catch (_) {
      // Server expiry is the fallback if the connection is already gone.
    } finally {
      _http.close(force: true);
    }
  }
}
