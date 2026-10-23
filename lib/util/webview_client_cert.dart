import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:server_core/server_core.dart';

import '../data/services/client_certificate_service.dart';

/// Answers a WebView's client certificate request with the one stored for
/// that host. Returning null leaves it to the platform, which on Windows means
/// WebView2's own picker.
Future<ClientCertResponse?> clientCertificateResponse(
  InAppWebViewController controller,
  URLAuthenticationChallenge challenge,
) async {
  final certificate = clientCertificateFor(challenge.protectionSpace.host);
  if (certificate == null) return null;
  try {
    final compat = compatPkcs12For(certificate);
    final file = await clientCertificateFile(certificate.host, 'p12');
    await file.writeAsBytes(compat.der);
    return ClientCertResponse(
      certificatePath: file.path,
      certificatePassword: compat.password,
      keyStoreType: 'PKCS12',
      action: ClientCertResponseAction.PROCEED,
    );
  } catch (_) {
    return null;
  }
}
