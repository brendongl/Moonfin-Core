import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/pkcs12_decoder.dart';

// An EC client certificate issued by a test CA, exported by OpenSSL 3 with its
// default AES and SHA-256 settings, and again with -legacy. Password "secret".
const _modern = '''
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
''';

const _legacy = '''
MIIFQgIBAzCCBQAGCSqGSIb3DQEHAaCCBPEEggTtMIIE6TCCA98GCSqGSIb3DQEHBqCCA9AwggPM
AgEAMIIDxQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQYwDgQI2FAHY1AIe8wCAggAgIIDmFKyY6ur
RF25UjCtfp91JIJJuQlzYGrKU2LQ3tEJV5Dcq3hEq0CdM/0CAYO+L85X9etyyNJfAsV15SQ3rs5b
TUXprGvKVSpLKusze/+QlCs+opOHqK4kbrXMyDsPqGeREo8KDv826nHc9z4wEx31Y23ldkx59/jK
ci7wQeukd7Fosq6iswCAgpnj5xhv/QgQkEYDHdupnqZLHipNRduNo5bquubzJtWHTEQwHKYQp9sr
LDq37EkNVaJ/FcYGMS0qU6Xm0KFx421j47SmzIC0WYeM4/u8+fXvH4EynL3ia544l78iFYp5zvEa
eDYzr5d+Fe02wvZTgOw1rjVV2k5aBltKYrqEx797ClIBMAicPYOpDRSNZus8cLdQDWndua44+Nmh
ffzBEdroiyf1Jq5ihAktRhde76UStC8/wyrTYQyfXF2H91AxBRCQBFZuWmVAx7WF8AgP4F65tKt9
K6u6pgPx8AiVrQsLHXJ+ztb4Y70RtKEoZPPVtma3xd1bsD7L/6UN/7p+5abuO00Asu/kvQr3c2A1
YWdPScGN5NUAp/McoYxMJJCaYbBwFXxcTXUzPPcCK+F5duhh0UUz9KwXq7MPC3zMtnslCebhplRz
igfqS1/jqQUIoZxzoTFRvvuThIC1jJcQFmfRQuDlg2xSubKs0qki66cXJo/SR5WKJnmt65K2ZwB5
xaR8hISL6qnq9fBlWfQJwNEgb7RBFsOIEgrHkDYyyzKSbUp2CiPbH70Gz6kWHK2aZE2GbZW5btbf
FZSJ6FYm9PT3IIKcv4kfCUN0ZUlpGz0U9JDIIuEo53yUa3cR15+yjt7NLsgchmau5tweMHlplShv
mmPzFBw0Z+nVWNbek48NzgNhCvqNkLoQ14gtFUZnJRux8wBFrs9dl682IOwF8u2RazwxCU/B1JKA
hgNrL5PDKxqFN9Yohh9sKwhktOkMtOyB613Gxet8aEbkUfi2Gp2iCWdUI0Rs9ph1EZa0Vil4MqA8
98A0hYdMqPo+ocC+lEk+SL+cJI+VaNGb+G/qBiLXHdshVfiJhNAzwQL694nO2k1sGSPue9P4Qhz9
uPxNa++sWFct53Erc4CZQKly+DiXn1yZ3ELUikj6qTmbIdOrQ1SMxPT5eNIodhndjuDNxL7gL3nR
LF6Ph3OQiBjjjjZJuc+OONkvefmsShwsh2FR/flqiUVluCbd6BouyrAlbvjF3t3Ht7ni5LwdKCp7
FaMEMIIBAgYJKoZIhvcNAQcBoIH0BIHxMIHuMIHrBgsqhkiG9w0BDAoBAqCBtDCBsTAcBgoqhkiG
9w0BDAEDMA4ECNvPDooovt4eAgIIAASBkD4h3Q8rYW4BjSyIGmZa1LnRbCdv1KFMnQliBw+KFOk2
uaUk2vFwcZTxPWoFwzEbiCleDDAcsIvZTYMl2mO3dNZhOuHClpMPbDsU+owT7SYiQdoCEpvagb7A
qX85ArSA2lg/aP1wyrnm8i1cyI4vlsDoymaR0nXpzRljdPmuUgI8ijwJEdGA+OhPbXWYOwylvjEl
MCMGCSqGSIb3DQEJFTEWBBTZ9TQdLN3kdJrlGZU8DeGia9gCdjA5MCEwCQYFKw4DAhoFAAQUVCIx
4R9/MNGmP5bOKxRgrEOidT0EECITu23RHHS6Z1ntG9GlTMcCAggA
''';

const _clientKey = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgIBOtFd52t/s0cGed
olzm4C0HJ83whYW0mF1Mh2p+/UyhRANCAAStt0CsKczeCtPU8wzUUwSSc8RccC2V
5DjPG0Cj08z+b/RC4yEuOxiGLDpvpOYNLelXTTcGTwrRjqNgS7AuJPKI
-----END PRIVATE KEY-----
''';

Uint8List _bytes(String b64) => base64.decode(b64.replaceAll('\n', ''));

void main() {
  for (final (name, file) in [
    ('OpenSSL 3 default', _modern),
    ('-legacy', _legacy),
  ]) {
    test('decodes a $name export', () {
      final decoded = decodePkcs12(_bytes(file), 'secret');

      expect(decoded.subject, 'moonfin-client');
      expect(decoded.keyPem, _clientKey);
      expect(decoded.notAfter.year, 2126);
      final chain = RegExp('BEGIN CERTIFICATE').allMatches(decoded.chainPem);
      expect(chain, hasLength(2));
    });
  }

  test('reports a wrong password', () {
    expect(
      () => decodePkcs12(_bytes(_modern), 'nope'),
      throwsA(
        isA<Pkcs12Exception>().having(
          (e) => e.error,
          'error',
          Pkcs12Error.wrongPassword,
        ),
      ),
    );
  });

  test('reports a file that is not a .p12', () {
    expect(
      () => decodePkcs12(Uint8List.fromList(utf8.encode(_clientKey)), 'secret'),
      throwsA(
        isA<Pkcs12Exception>().having(
          (e) => e.error,
          'error',
          Pkcs12Error.invalid,
        ),
      ),
    );
  });

  test('re-wraps the material as a .p12 that decodes back', () {
    final original = decodePkcs12(_bytes(_legacy), 'secret');
    final compat = buildCompatPkcs12(
      chainPem: original.chainPem,
      keyPem: original.keyPem,
    );
    final decoded = decodePkcs12(compat.der, compat.password);

    expect(decoded.chainPem, original.chainPem);
    expect(decoded.keyPem, original.keyPem);
  });
}
