import 'package:media_kit/media_kit.dart';
import 'package:server_core/server_core.dart';

import '../data/services/client_certificate_service.dart';

/// Points mpv at the client certificate for [url]'s host, or clears the one a
/// previous open set. mpv only takes file paths and has no key password, so
/// the key is written unencrypted to app-private storage.
Future<void> applyMpvClientCertificate(Player player, String url) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    final certificate = clientCertificateFor(Uri.tryParse(url)?.host ?? '');
    var certPath = '';
    var keyPath = '';
    if (certificate != null) {
      final certFile = await clientCertificateFile(certificate.host, 'crt');
      final keyFile = await clientCertificateFile(certificate.host, 'key');
      await certFile.writeAsString(certificate.chainPem);
      await keyFile.writeAsString(certificate.keyPem);
      certPath = certFile.path;
      keyPath = keyFile.path;
    }
    // NativePlayer's web stub has no setProperty, so the web build needs dynamic here.
    final dynamic native = platform;
    await native.setProperty('tls-cert-file', certPath);
    await native.setProperty('tls-key-file', keyPath);
  } catch (_) {
    // Playback still goes ahead, and a server that needs the certificate
    // refuses it.
  }
}
