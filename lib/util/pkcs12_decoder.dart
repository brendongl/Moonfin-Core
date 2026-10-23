import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/rc2_engine.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/key_derivators/pkcs12_parameter_generator.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

/// A .p12/.pfx decoded to PEM, with the leaf's subject and expiry for display.
class Pkcs12Decoded {
  const Pkcs12Decoded({
    required this.keyPem,
    required this.chainPem,
    required this.subject,
    required this.notAfter,
  });

  /// The private key as unencrypted PKCS#8.
  final String keyPem;

  /// The leaf first, then whatever issued it.
  final String chainPem;
  final String subject;
  final DateTime notAfter;
}

enum Pkcs12Error { wrongPassword, unsupported, invalid }

class Pkcs12Exception implements Exception {
  const Pkcs12Exception(this.error);

  final Pkcs12Error error;

  @override
  String toString() => 'Pkcs12Exception(${error.name})';
}

const _oidData = '1.2.840.113549.1.7.1';
const _oidEncryptedData = '1.2.840.113549.1.7.6';
const _oidKeyBag = '1.2.840.113549.1.12.10.1.1';
const _oidShroudedKeyBag = '1.2.840.113549.1.12.10.1.2';
const _oidCertBag = '1.2.840.113549.1.12.10.1.3';
const _oidSafeContentsBag = '1.2.840.113549.1.12.10.1.6';
const _oidX509Certificate = '1.2.840.113549.1.9.22.1';
const _oidLocalKeyId = '1.2.840.113549.1.9.21';
const _oidPbes2 = '1.2.840.113549.1.5.13';
const _oidPbkdf2 = '1.2.840.113549.1.5.12';
const _oidHmacSha1 = '1.2.840.113549.2.7';
const _oidPbeSha1TripleDes = '1.2.840.113549.1.12.1.3';
const _oidSha1 = '1.3.14.3.2.26';
const _oidCommonName = '2.5.4.3';

/// Decodes a .p12/.pfx protected by [password].
///
/// Covers the PBES2 (PBKDF2 with AES or 3DES) that OpenSSL 3 writes by default
/// and the older PKCS#12 PBE ciphers that `-legacy` and Windows exports use.
Pkcs12Decoded decodePkcs12(Uint8List data, String password) {
  try {
    return _decode(data, password);
  } on Pkcs12Exception {
    rethrow;
  } catch (_) {
    throw const Pkcs12Exception(Pkcs12Error.invalid);
  }
}

Pkcs12Decoded _decode(Uint8List data, String password) {
  final pfx = _Asn1.parse(data);
  final authSafe = pfx[1];
  if (authSafe[0].oid != _oidData) {
    throw const Pkcs12Exception(Pkcs12Error.unsupported);
  }
  final authSafeBytes = authSafe[1][0].octets;
  if (pfx.children.length > 2) _verifyMac(pfx[2], authSafeBytes, password);

  final keys = <_Entry>[];
  final certs = <_Entry>[];
  for (final info in _Asn1.parse(authSafeBytes).children) {
    switch (info[0].oid) {
      case _oidData:
        _collectBags(_Asn1.parse(info[1][0].octets), password, keys, certs);
      case _oidEncryptedData:
        final content = info[1][0][1];
        final plain = _decrypt(content[1], content[2].octets, password);
        _collectBags(_Asn1.parse(plain), password, keys, certs);
    }
  }
  if (keys.isEmpty || certs.isEmpty) {
    throw const Pkcs12Exception(Pkcs12Error.invalid);
  }

  final key = keys.first;
  final leaf = certs.firstWhere(
    (c) => key.keyId != null && _bytesEqual(c.keyId, key.keyId),
    orElse: () => certs.firstWhere(
      (c) => !certs.any(
        (other) => other != c && _bytesEqual(other.cert.issuer, c.cert.subject),
      ),
      orElse: () => certs.first,
    ),
  );
  final chain = [leaf];
  while (true) {
    final current = chain.last.cert;
    if (_bytesEqual(current.issuer, current.subject)) break;
    final issuer = certs.where(
      (c) => !chain.contains(c) && _bytesEqual(c.cert.subject, current.issuer),
    );
    if (issuer.isEmpty) break;
    chain.add(issuer.first);
  }

  return Pkcs12Decoded(
    keyPem: _pem('PRIVATE KEY', key.der),
    chainPem: chain.map((c) => _pem('CERTIFICATE', c.der)).join(),
    subject: leaf.cert.commonName,
    notAfter: leaf.cert.notAfter,
  );
}

void _collectBags(
  _Asn1 safeContents,
  String password,
  List<_Entry> keys,
  List<_Entry> certs,
) {
  for (final bag in safeContents.children) {
    final value = bag[1][0];
    final keyId = _localKeyId(bag);
    switch (bag[0].oid) {
      case _oidKeyBag:
        keys.add(_Entry(value.der, keyId));
      case _oidShroudedKeyBag:
        keys.add(_Entry(_decrypt(value[0], value[1].octets, password), keyId));
      case _oidCertBag when value[0].oid == _oidX509Certificate:
        certs.add(_Entry(value[1][0].octets, keyId));
      case _oidSafeContentsBag:
        _collectBags(value, password, keys, certs);
    }
  }
}

Uint8List? _localKeyId(_Asn1 bag) {
  if (bag.children.length < 3) return null;
  for (final attribute in bag[2].children) {
    if (attribute[0].oid == _oidLocalKeyId) return attribute[1][0].octets;
  }
  return null;
}

void _verifyMac(_Asn1 macData, Uint8List content, String password) {
  final digestInfo = macData[0];
  final algorithm = digestInfo[0][0].oid;
  final salt = macData[1].octets;
  final iterations = macData.children.length > 2 ? macData[2].intValue : 1;
  final mac = _pkcs12Mac(algorithm, salt, iterations, password, content);
  if (!_bytesEqual(mac, digestInfo[1].octets)) {
    throw const Pkcs12Exception(Pkcs12Error.wrongPassword);
  }
}

Uint8List _pkcs12Mac(
  String? digestOid,
  Uint8List salt,
  int iterations,
  String password,
  Uint8List content,
) {
  final digest = _digest(digestOid);
  final generator = PKCS12ParametersGenerator(digest)
    ..init(_bmpPassword(password), salt, iterations);
  final key = generator.generateDerivedMacParameters(digest.digestSize);
  return (HMac.withDigest(_digest(digestOid))..init(key)).process(content);
}

Uint8List _decrypt(_Asn1 algorithm, Uint8List data, String password) {
  final oid = algorithm[0].oid;
  final params = algorithm[1];
  if (oid == _oidPbes2) {
    final kdf = params[0];
    final scheme = params[1];
    if (kdf[0].oid != _oidPbkdf2) {
      throw const Pkcs12Exception(Pkcs12Error.unsupported);
    }
    final kdfParams = kdf[1];
    var prf = _oidHmacSha1;
    for (final extra in kdfParams.children.skip(2)) {
      if (extra.tag == 0x30) prf = extra[0].oid ?? prf;
    }
    final (engine, keyLength) = switch (scheme[0].oid) {
      '2.16.840.1.101.3.4.1.2' => (AESEngine(), 16),
      '2.16.840.1.101.3.4.1.22' => (AESEngine(), 24),
      '2.16.840.1.101.3.4.1.42' => (AESEngine(), 32),
      '1.2.840.113549.3.7' => (DESedeEngine(), 24),
      _ => throw const Pkcs12Exception(Pkcs12Error.unsupported),
    };
    final key = Uint8List(keyLength);
    PBKDF2KeyDerivator(HMac.withDigest(_digest(prf)))
      ..init(
        Pbkdf2Parameters(kdfParams[0].octets, kdfParams[1].intValue, keyLength),
      )
      ..deriveKey(utf8.encode(password), 0, key, 0);
    return _cbc(false, engine, KeyParameter(key), scheme[1].octets, data);
  }

  final (BlockCipher engine, int keyLength, int? rc2Bits) = switch (oid) {
    _oidPbeSha1TripleDes => (DESedeEngine(), 24, null),
    '1.2.840.113549.1.12.1.4' => (DESedeEngine(), 16, null),
    '1.2.840.113549.1.12.1.5' => (RC2Engine(), 16, 128),
    '1.2.840.113549.1.12.1.6' => (RC2Engine(), 5, 40),
    _ => throw const Pkcs12Exception(Pkcs12Error.unsupported),
  };
  final derived =
      (PKCS12ParametersGenerator(
            SHA1Digest(),
          )..init(_bmpPassword(password), params[0].octets, params[1].intValue))
          .generateDerivedParametersWithIV(keyLength, 8);
  final key = (derived.parameters as KeyParameter).key;
  return _cbc(
    false,
    engine,
    rc2Bits == null ? KeyParameter(key) : RC2Parameters(key, bits: rc2Bits),
    derived.iv,
    data,
  );
}

Uint8List _cbc(
  bool encrypt,
  BlockCipher engine,
  CipherParameters key,
  Uint8List iv,
  Uint8List data,
) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(engine))
    ..init(
      encrypt,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters?>(
        ParametersWithIV(key, iv),
        null,
      ),
    );
  try {
    return cipher.process(data);
  } on ArgumentError {
    // Without a MAC to check first, a bad pad is the only sign of a wrong password.
    throw const Pkcs12Exception(Pkcs12Error.wrongPassword);
  }
}

Digest _digest(String? oid) => switch (oid) {
  _oidSha1 || _oidHmacSha1 => SHA1Digest(),
  '2.16.840.1.101.3.4.2.4' || '1.2.840.113549.2.8' => SHA224Digest(),
  '2.16.840.1.101.3.4.2.1' || '1.2.840.113549.2.9' => SHA256Digest(),
  '2.16.840.1.101.3.4.2.2' || '1.2.840.113549.2.10' => SHA384Digest(),
  '2.16.840.1.101.3.4.2.3' || '1.2.840.113549.2.11' => SHA512Digest(),
  _ => throw const Pkcs12Exception(Pkcs12Error.unsupported),
};

Uint8List _bmpPassword(String password) {
  final bytes = Uint8List(password.length * 2 + 2);
  for (var i = 0; i < password.length; i++) {
    final unit = password.codeUnitAt(i);
    bytes[i * 2] = unit >> 8;
    bytes[i * 2 + 1] = unit & 0xff;
  }
  return bytes;
}

bool _bytesEqual(Uint8List? a, Uint8List? b) {
  if (a == null || b == null || a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _pem(String label, Uint8List der) {
  final b64 = base64.encode(der);
  final buffer = StringBuffer('-----BEGIN $label-----\n');
  for (var i = 0; i < b64.length; i += 64) {
    buffer.writeln(b64.substring(i, min(i + 64, b64.length)));
  }
  buffer.writeln('-----END $label-----');
  return buffer.toString();
}

List<Uint8List> _pemBlocks(String pem, String label) =>
    RegExp('-----BEGIN $label-----([^-]+)-----END $label-----')
        .allMatches(pem)
        .map((m) => base64.decode(m[1]!.replaceAll(RegExp(r'\s'), '')))
        .toList();

class _Entry {
  _Entry(this.der, this.keyId);

  final Uint8List der;
  final Uint8List? keyId;
  late final _Certificate cert = _Certificate(_Asn1.parse(der));
}

class _Certificate {
  _Certificate(_Asn1 certificate) {
    final tbs = certificate[0];
    final offset = tbs[0].tag == 0xa0 ? 1 : 0;
    issuer = tbs[offset + 2].der;
    notAfter = _time(tbs[offset + 3][1]);
    final subjectName = tbs[offset + 4];
    subject = subjectName.der;
    commonName = _commonName(subjectName);
  }

  late final Uint8List issuer;
  late final Uint8List subject;
  late final String commonName;
  late final DateTime notAfter;

  static String _commonName(_Asn1 name) {
    for (final rdn in name.children) {
      for (final attribute in rdn.children) {
        if (attribute[0].oid != _oidCommonName) continue;
        final value = attribute[1];
        if (value.tag == 0x1e) {
          final units = value.content;
          return String.fromCharCodes([
            for (var i = 0; i + 1 < units.length; i += 2)
              (units[i] << 8) | units[i + 1],
          ]);
        }
        return utf8.decode(value.content, allowMalformed: true);
      }
    }
    return '';
  }

  static DateTime _time(_Asn1 node) {
    final text = ascii.decode(node.content);
    final yearDigits = node.tag == 0x17 ? 2 : 4;
    var year = int.parse(text.substring(0, yearDigits));
    if (yearDigits == 2) year += year < 50 ? 2000 : 1900;
    int field(int index) {
      final start = yearDigits + index * 2;
      return int.parse(text.substring(start, start + 2));
    }

    return DateTime.utc(year, field(0), field(1), field(2), field(3), field(4));
  }
}

/// Just enough BER to walk a .p12, including the indefinite lengths and split
/// octet strings that Windows exports use.
class _Asn1 {
  _Asn1(this.tag, this.content, this.der, this.children);

  factory _Asn1.parse(Uint8List data) => _read(data, 0).$1;

  final int tag;
  final Uint8List content;
  final Uint8List der;
  final List<_Asn1> children;

  bool get isConstructed => tag & 0x20 != 0;

  _Asn1 operator [](int index) => children[index];

  Uint8List get octets => isConstructed
      ? Uint8List.fromList([for (final child in children) ...child.octets])
      : content;

  int get intValue => content.fold(0, (value, byte) => (value << 8) | byte);

  String? get oid {
    if (tag != 0x06 || content.isEmpty) return null;
    final parts = [content[0] ~/ 40, content[0] % 40];
    var value = 0;
    for (final byte in content.skip(1)) {
      value = (value << 7) | (byte & 0x7f);
      if (byte & 0x80 == 0) {
        parts.add(value);
        value = 0;
      }
    }
    return parts.join('.');
  }

  static (_Asn1, int) _read(Uint8List data, int offset) {
    final tag = data[offset];
    if (tag & 0x1f == 0x1f) throw const Pkcs12Exception(Pkcs12Error.invalid);
    var pos = offset + 1;
    final first = data[pos++];
    final children = <_Asn1>[];
    final start = pos;
    if (first == 0x80) {
      if (tag & 0x20 == 0) throw const Pkcs12Exception(Pkcs12Error.invalid);
      while (data[pos] != 0 || data[pos + 1] != 0) {
        final (child, next) = _read(data, pos);
        children.add(child);
        pos = next;
      }
      return (
        _Asn1(
          tag,
          Uint8List.sublistView(data, start, pos),
          Uint8List.sublistView(data, offset, pos + 2),
          children,
        ),
        pos + 2,
      );
    }
    var length = first;
    if (first > 0x80) {
      length = 0;
      for (var i = 0; i < (first & 0x7f); i++) {
        length = (length << 8) | data[pos++];
      }
    }
    final end = pos + length;
    if (end > data.length) throw const Pkcs12Exception(Pkcs12Error.invalid);
    final contentStart = pos;
    if (tag & 0x20 != 0) {
      while (pos < end) {
        final (child, next) = _read(data, pos);
        children.add(child);
        pos = next;
      }
    }
    return (
      _Asn1(
        tag,
        Uint8List.sublistView(data, contentStart, end),
        Uint8List.sublistView(data, offset, end),
        children,
      ),
      end,
    );
  }
}

const _compatIterations = 2048;

/// Re-wraps PEM material as a .p12 that uses SHA1 and 3DES throughout, under a
/// fresh random password. Apple's `SecPKCS12Import` and the WebView
/// client-certificate handlers need a .p12, and older OS versions can't open
/// the AES ones OpenSSL 3 writes.
({Uint8List der, String password}) buildCompatPkcs12({
  required String chainPem,
  required String keyPem,
}) {
  final random = Random.secure();
  Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  final password = base64Url.encode(randomBytes(18));
  final certs = _pemBlocks(chainPem, 'CERTIFICATE');
  final key = _pemBlocks(keyPem, 'PRIVATE KEY').single;

  final keyId = SHA1Digest().process(certs.first);
  final keyIdAttribute = _derSet([
    _derSeq([
      _derOid(_oidLocalKeyId),
      _derSet([_derOctets(keyId)]),
    ]),
  ]);

  Uint8List pbeAlgorithm(Uint8List salt) => _derSeq([
    _derOid(_oidPbeSha1TripleDes),
    _derSeq([_derOctets(salt), _derInt(_compatIterations)]),
  ]);
  Uint8List pbeEncrypt(Uint8List data, Uint8List salt) {
    final derived =
        (PKCS12ParametersGenerator(SHA1Digest())
              ..init(_bmpPassword(password), salt, _compatIterations))
            .generateDerivedParametersWithIV(24, 8);
    return _cbc(
      true,
      DESedeEngine(),
      derived.parameters as KeyParameter,
      derived.iv,
      data,
    );
  }

  final certBags = _derSeq([
    for (var i = 0; i < certs.length; i++)
      _derSeq([
        _derOid(_oidCertBag),
        _derTag(
          0xa0,
          _derSeq([
            _derOid(_oidX509Certificate),
            _derTag(0xa0, _derOctets(certs[i])),
          ]),
        ),
        if (i == 0) keyIdAttribute,
      ]),
  ]);
  final keySalt = randomBytes(8);
  final keyBags = _derSeq([
    _derSeq([
      _derOid(_oidShroudedKeyBag),
      _derTag(
        0xa0,
        _derSeq([pbeAlgorithm(keySalt), _derOctets(pbeEncrypt(key, keySalt))]),
      ),
      keyIdAttribute,
    ]),
  ]);
  final certSalt = randomBytes(8);
  final authSafe = _derSeq([
    _derSeq([
      _derOid(_oidEncryptedData),
      _derTag(
        0xa0,
        _derSeq([
          _derInt(0),
          _derSeq([
            _derOid(_oidData),
            pbeAlgorithm(certSalt),
            _derTag(0x80, pbeEncrypt(certBags, certSalt)),
          ]),
        ]),
      ),
    ]),
    _derSeq([_derOid(_oidData), _derTag(0xa0, _derOctets(keyBags))]),
  ]);

  final macSalt = randomBytes(8);
  final mac = _pkcs12Mac(
    _oidSha1,
    macSalt,
    _compatIterations,
    password,
    authSafe,
  );
  final pfx = _derSeq([
    _derInt(3),
    _derSeq([_derOid(_oidData), _derTag(0xa0, _derOctets(authSafe))]),
    _derSeq([
      _derSeq([
        _derSeq([_derOid(_oidSha1), _derTag(0x05, const [])]),
        _derOctets(mac),
      ]),
      _derOctets(macSalt),
      _derInt(_compatIterations),
    ]),
  ]);
  return (der: pfx, password: password);
}

Uint8List _derTag(int tag, List<int> content) {
  final length = <int>[];
  if (content.length < 0x80) {
    length.add(content.length);
  } else {
    for (var v = content.length; v > 0; v >>= 8) {
      length.insert(0, v & 0xff);
    }
    length.insert(0, 0x80 | length.length);
  }
  return Uint8List.fromList([tag, ...length, ...content]);
}

Uint8List _derSeq(List<Uint8List> items) =>
    _derTag(0x30, [for (final item in items) ...item]);

Uint8List _derSet(List<Uint8List> items) =>
    _derTag(0x31, [for (final item in items) ...item]);

Uint8List _derOctets(List<int> bytes) => _derTag(0x04, bytes);

Uint8List _derInt(int value) {
  final bytes = <int>[];
  var v = value;
  do {
    bytes.insert(0, v & 0xff);
    v >>= 8;
  } while (v > 0);
  if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
  return _derTag(0x02, bytes);
}

Uint8List _derOid(String oid) {
  final parts = oid.split('.').map(int.parse).toList();
  final bytes = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    for (var v = part >> 7; v > 0; v >>= 7) {
      chunk.insert(0, 0x80 | (v & 0x7f));
    }
    bytes.addAll(chunk);
  }
  return _derTag(0x06, bytes);
}
