import 'client_certificate_store_base.dart';

// The browser owns TLS on web, so there's nothing to keep.
class ClientCertificateStoreImpl implements ClientCertificateStore {
  @override
  bool consumeSecureStorageUnavailable() => false;

  @override
  Future<void> save(StoredClientCertificate certificate) async {}

  @override
  Future<StoredClientCertificate?> get(String host) async => null;

  @override
  Future<List<StoredClientCertificate>> getAll() async => const [];

  @override
  Future<void> remove(String host) async {}
}

ClientCertificateStore createClientCertificateStore() =>
    ClientCertificateStoreImpl();
