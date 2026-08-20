import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the sink the OTA updater feeds its chunked sha256 conversion.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Digest _streamed(List<List<int>> chunks) {
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  for (final c in chunks) {
    hasher.add(c);
  }
  hasher.close();
  return sink.value!;
}

// The updater hashes the APK as the bytes arrive instead of re-reading the
// finished file, because a second pass over ~100 MB on an Allwinner box looked
// like a hang at 100%. That only holds if the incremental digest is identical
// to the one-shot digest for any chunk split the network happens to produce.
void main() {
  test('chunked digest matches the one-shot digest', () {
    final bytes = utf8.encode('moonfin' * 5000);
    final rng = Random(20260820);

    for (var trial = 0; trial < 25; trial++) {
      final chunks = <List<int>>[];
      var offset = 0;
      while (offset < bytes.length) {
        final take = min(1 + rng.nextInt(4096), bytes.length - offset);
        chunks.add(bytes.sublist(offset, offset + take));
        offset += take;
      }
      expect(_streamed(chunks), equals(sha256.convert(bytes)),
          reason: 'split into ${chunks.length} chunks');
    }
  });

  test('an empty body still closes to a real digest', () {
    expect(_streamed(const []), equals(sha256.convert(const [])));
  });

  test('a truncated stream does NOT match, so verification still fails', () {
    final bytes = utf8.encode('moonfin' * 5000);
    expect(_streamed([bytes.sublist(0, bytes.length - 1)]),
        isNot(equals(sha256.convert(bytes))));
  });
}
