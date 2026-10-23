import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../util/pkcs12_decoder.dart';

/// A one-time page on the LAN that lets a phone send a .p12 and its password
/// to a TV, which has no file picker. It answers only at a random path and
/// shuts down after a certificate decodes or ten minutes pass.
class CertificateUploadServer {
  CertificateUploadServer({required this.describeError});

  /// The message the phone shows when a file doesn't decode.
  final String Function(Pkcs12Exception error) describeError;

  static const _maxBodyBytes = 64 * 1024;

  final _received = Completer<Pkcs12Decoded>();
  final String path = '/${_randomToken()}';
  HttpServer? _server;
  Timer? _timeout;

  int? get port => _server?.port;

  /// Completes with the first upload that decodes.
  Future<Pkcs12Decoded> get received => _received.future;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _timeout = Timer(const Duration(minutes: 10), close);
    _server!.listen(_handle);
  }

  void close() {
    _timeout?.cancel();
    _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != path) {
      response.statusCode = HttpStatus.notFound;
    } else if (request.method == 'GET') {
      response
        ..headers.contentType = ContentType.html
        ..write(_page);
    } else if (request.method != 'POST') {
      response.statusCode = HttpStatus.methodNotAllowed;
    } else {
      final (status, message) = await _accept(request);
      response
        ..statusCode = status
        ..headers.contentType = ContentType.text
        ..write(message);
    }
    await response.close();
    // Shut down only once the phone has its answer, since a forced close
    // drops the reply still on its way.
    if (_received.isCompleted) close();
  }

  Future<(int, String)> _accept(HttpRequest request) async {
    if (_received.isCompleted) return (HttpStatus.gone, '');
    final body = BytesBuilder(copy: false);
    await for (final chunk in request) {
      body.add(chunk);
      if (body.length > _maxBodyBytes) {
        return (HttpStatus.requestEntityTooLarge, '');
      }
    }
    final Uint8List p12;
    final String password;
    try {
      final json = jsonDecode(utf8.decode(body.takeBytes())) as Map;
      p12 = base64.decode(json['p12Base64'] as String);
      password = json['password'] as String;
    } catch (_) {
      return (HttpStatus.badRequest, '');
    }
    try {
      final decoded = decodePkcs12(p12, password);
      if (_received.isCompleted) return (HttpStatus.gone, '');
      _received.complete(decoded);
    } on Pkcs12Exception catch (e) {
      return (HttpStatus.unprocessableEntity, describeError(e));
    }
    return (HttpStatus.ok, '');
  }

  static String _randomToken() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static const _page = '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Moonfin</title>
<style>
body{font-family:system-ui,sans-serif;background:#111;color:#eee;max-width:20rem;margin:2rem auto;padding:0 1rem}
input,button{width:100%;margin:.4rem 0;padding:.6rem;box-sizing:border-box;font-size:1rem}
button{background:#7c3aed;color:#fff;border:0;border-radius:.4rem}
#msg{min-height:1.2rem;white-space:pre-wrap}
</style></head><body>
<h2>Send a client certificate</h2>
<p>Pick the .p12 or .pfx file and enter its password. It goes straight to your TV over this network.</p>
<input type="file" id="file" accept=".p12,.pfx">
<input type="password" id="password" placeholder="Password">
<button id="send">Send</button>
<div id="msg"></div>
<script>
document.getElementById('send').onclick = async () => {
  const file = document.getElementById('file').files[0];
  const msg = document.getElementById('msg');
  if (!file) { msg.textContent = 'Choose a file first.'; return; }
  const bytes = new Uint8Array(await file.arrayBuffer());
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  msg.textContent = 'Sending...';
  try {
    const res = await fetch(location.pathname, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({p12Base64: btoa(bin), password: document.getElementById('password').value})
    });
    msg.textContent = res.ok ? 'Sent. Finish on your TV.' : (await res.text() || 'That didn\\'t work. Try again.');
  } catch (e) {
    msg.textContent = 'The TV stopped listening. Start again from the TV.';
  }
};
</script>
</body></html>
''';
}
