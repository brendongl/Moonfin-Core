/// A client certificate bound to the one host it may be presented to.
class ClientCertificateMaterial {
  const ClientCertificateMaterial({
    required this.host,
    required this.chainPem,
    required this.keyPem,
  });

  final String host;

  /// The leaf first, then whatever issued it.
  final String chainPem;

  /// An unencrypted PKCS#8 key.
  final String keyPem;
}

final _certificates = <String, ClientCertificateMaterial>{};

/// Replaces the certificates connections may present. Each connection looks
/// its host up when it opens, so a change applies without rebuilding clients.
void setClientCertificates(Iterable<ClientCertificateMaterial> certificates) {
  _certificates
    ..clear()
    ..addEntries(
      certificates.map((c) => MapEntry(normalizeCertificateHost(c.host), c)),
    );
}

ClientCertificateMaterial? clientCertificateFor(String host) =>
    _certificates[normalizeCertificateHost(host)];

Iterable<ClientCertificateMaterial> get clientCertificates =>
    _certificates.values;

String normalizeCertificateHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized.endsWith('.')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}
