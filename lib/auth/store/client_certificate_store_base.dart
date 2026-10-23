import 'package:server_core/server_core.dart';

/// A client certificate as stored for one host, with the leaf's subject and
/// expiry kept for display.
class StoredClientCertificate {
  const StoredClientCertificate({
    required this.host,
    required this.chainPem,
    required this.keyPem,
    required this.subject,
    required this.notAfter,
  });

  factory StoredClientCertificate.fromJson(
    String host,
    Map<String, dynamic> json,
  ) {
    return StoredClientCertificate(
      host: host,
      chainPem: json['chainPem'] as String? ?? '',
      keyPem: json['keyPem'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      notAfter:
          DateTime.tryParse(json['notAfter'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String host;
  final String chainPem;
  final String keyPem;
  final String subject;
  final DateTime notAfter;

  ClientCertificateMaterial get material =>
      ClientCertificateMaterial(host: host, chainPem: chainPem, keyPem: keyPem);

  Map<String, dynamic> toJson() => {
    'chainPem': chainPem,
    'keyPem': keyPem,
    'subject': subject,
    'notAfter': notAfter.toIso8601String(),
  };
}

abstract class ClientCertificateStore {
  static const keyPrefix = 'client_cert_';

  /// True once since the last call if a write failed for lack of a secret
  /// store.
  bool consumeSecureStorageUnavailable();

  Future<void> save(StoredClientCertificate certificate);
  Future<StoredClientCertificate?> get(String host);
  Future<List<StoredClientCertificate>> getAll();
  Future<void> remove(String host);
}
