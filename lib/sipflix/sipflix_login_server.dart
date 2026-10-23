import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sipflix: a tiny LAN web server so customers can type their credentials on a
/// phone instead of the TV remote. It serves a styled login form; submitted
/// credentials are handed to [onCredentials], and the phone is told how the
/// sign-in went (its answer is the message to show, null for success). Ported
/// from the old Kotlin `LoginServer` (NanoHTTPD) — same port and flow.
class SipflixLoginServer {
  static const int port = 8765;

  final String serverName;
  final Future<String?> Function(String username, String password)
  onCredentials;

  /// How long the phone waits for an answer. A server choice waiting on the
  /// TV outlasts it; the phone is then pointed at the TV instead.
  static const Duration answerWait = Duration(seconds: 30);
  HttpServer? _server;
  bool _accepting = true;
  final Duration responseTimeout;
  int? get listeningPort => _server?.port;

  SipflixLoginServer({
    required this.serverName,
    required this.onCredentials,
    this.responseTimeout = answerWait,
  });

  bool get isRunning => _server != null;

  Future<void> start({int bindPort = port}) async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, bindPort);
    _server!.listen(_handle, onError: (_) {});
  }

  void stopAccepting() {
    _accepting = false;
  }

  Future<void> stop() async {
    stopAccepting();
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.method == 'GET' && req.uri.path == '/') {
        res.headers.contentType = ContentType.html;
        res.write(_loginHtml(serverName));
      } else if (req.method == 'POST' && req.uri.path == '/login') {
        if (!_accepting) {
          res.statusCode = HttpStatus.gone;
          res.write('The TV sign-in screen is closed. Open a new QR code.');
          return;
        }
        final bytes = <int>[];
        await for (final chunk in req.timeout(const Duration(seconds: 10))) {
          bytes.addAll(chunk);
          if (bytes.length > 4096) {
            res.statusCode = HttpStatus.requestEntityTooLarge;
            res.write('Request too large');
            return;
          }
        }
        final body = utf8.decode(bytes);
        final params = Uri.splitQueryString(body);
        final username = (params['username'] ?? '').trim();
        final password = params['password'] ?? '';
        if (username.isEmpty) {
          res.statusCode = HttpStatus.badRequest;
          res.write('Please enter a username');
          return;
        }
        final error = await onCredentials(username, password)
            .timeout(
              responseTimeout,
              onTimeout: () => 'The TV has not finished signing in. Check the TV screen; this is not a confirmed sign-in.',
            )
            .catchError((Object _) => 'Sign-in failed. Please try again.');
        if (error == null) {
          res.statusCode = HttpStatus.ok;
          res.write('OK');
        } else {
          res.statusCode = HttpStatus.unauthorized;
          res.headers.contentType = ContentType.text;
          res.write(error);
        }
      } else {
        res.statusCode = HttpStatus.notFound;
        res.write('Not Found');
      }
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// The box's LAN IPv4 address (prefers private ranges).
  static Future<String?> localIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (a.address.startsWith('192.168.') ||
              a.address.startsWith('10.') ||
              a.address.startsWith('172.')) {
            return a.address;
          }
        }
      }
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }

  static String _loginHtml(String serverName) =>
      '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Login to $serverName</title>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  background:linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%);
  min-height:100vh; display:flex; align-items:center; justify-content:center; padding:20px; }
.container { width:100%; max-width:400px; background:rgba(255,255,255,0.96);
  border-radius:16px; padding:40px 30px; box-shadow:0 20px 60px rgba(0,0,0,0.3); }
h1 { color:#1a1a2e; margin-bottom:8px; font-size:24px; text-align:center; }
.subtitle { color:#666; margin-bottom:30px; font-size:14px; text-align:center; }
.form-group { margin-bottom:20px; }
label { display:block; margin-bottom:8px; color:#333; font-weight:500; font-size:14px; }
input { width:100%; padding:14px; border:2px solid #e0e0e0; border-radius:8px; font-size:16px; }
input:focus { outline:none; border-color:#0f3460; }
button { width:100%; padding:16px; background:linear-gradient(135deg,#1a1a2e 0%,#0f3460 100%);
  color:#fff; border:none; border-radius:8px; font-size:16px; font-weight:600; cursor:pointer; }
button:disabled { opacity:0.6; }
.status { margin-top:20px; padding:12px; border-radius:8px; text-align:center; display:none; }
.status.success { background:#d4edda; color:#155724; display:block; }
.status.error { background:#f8d7da; color:#721c24; display:block; }
.status.loading { background:#cce5ff; color:#004085; display:block; }
</style>
</head>
<body>
<div class="container">
<h1>Login to $serverName</h1>
<p class="subtitle">Enter your credentials to sign in on your TV</p>
<p class="subtitle">Don't know your details? <a href="https://wa.me/84387592427" rel="noreferrer">Message FlixBot</a></p>
<form id="loginForm">
<div class="form-group"><label for="username">Username</label>
<input type="text" id="username" name="username" required autocomplete="username" autofocus></div>
<div class="form-group"><label for="password">Password</label>
<input type="password" id="password" name="password" autocomplete="current-password"></div>
<button type="submit" id="submitBtn">Sign In</button>
</form>
<div id="status" class="status"></div>
</div>
<script>
const form=document.getElementById('loginForm');
const submitBtn=document.getElementById('submitBtn');
const status=document.getElementById('status');
form.addEventListener('submit',async(e)=>{
  e.preventDefault();
  const username=document.getElementById('username').value.trim();
  const password=document.getElementById('password').value;
  if(!username){status.className='status error';status.textContent='Please enter a username';return;}
  submitBtn.disabled=true;status.className='status loading';status.textContent='Signing in...';
  try{
    const r=await fetch('/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:'username='+encodeURIComponent(username)+'&password='+encodeURIComponent(password)});
    if(r.ok){status.className='status success';status.textContent='Done! Check your TV screen.';form.reset();}
    else{status.className='status error';status.textContent=(await r.text())||'Sign-in failed. Please try again.';}
  }catch(err){status.className='status error';status.textContent='Could not reach the TV. Please try again.';}
  finally{submitBtn.disabled=false;}
});
</script>
</body>
</html>
''';
}
