export 'client_certificate_store_base.dart';

import 'client_certificate_store_base.dart';
import 'client_certificate_store_io.dart'
    if (dart.library.js_interop) 'client_certificate_store_web.dart'
    as impl;

ClientCertificateStore createClientCertificateStore() =>
    impl.createClientCertificateStore();
