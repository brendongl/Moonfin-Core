import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_bandwidth_probe.dart';

// The sampling math behind every preflight verdict. Extracted so it can be
// checked without a network: on 2026-08-21 the probe reported ~1.5 Mbps on a
// link doing 20+, and there was no way to tell a bad calculation from a starved
// socket without pinning the arithmetic down first.
void main() {
  // 10 MB delivered evenly over 4s = 20 Mbps, sampled every 100ms.
  List<(int, int)> evenTransfer({
    required int totalBytes,
    required int durationUs,
    int steps = 40,
  }) =>
      [
        for (var i = 1; i <= steps; i++)
          (durationUs ~/ steps * i, totalBytes ~/ steps * i),
      ];

  test('an even transfer past warm-up reads as its real rate', () {
    final r = sipflixThroughputFrom(
      samples: evenTransfer(totalBytes: 10000000, durationUs: 4000000),
      warmupBytes: 2000000,
      burstWindowUs: 500000,
    )!;
    expect(r.sustainedMbps, closeTo(20, 0.6));
    expect(r.burstMbps, greaterThanOrEqualTo(r.sustainedMbps));
  });

  test('slow-start is excluded: a slow first MB does not drag it down', () {
    // 1 MB crawls out over 3s, then 9 MB arrives in 3s (=24 Mbps).
    final samples = <(int, int)>[
      for (var i = 1; i <= 10; i++) (300000 * i, 100000 * i),
      for (var i = 1; i <= 30; i++) (3000000 + 100000 * i, 1000000 + 300000 * i),
    ];
    final r = sipflixThroughputFrom(
      samples: samples,
      warmupBytes: 2000000,
      burstWindowUs: 500000,
    )!;
    expect(r.sustainedMbps, greaterThan(15),
        reason: 'the warm-up crawl must not count as the link speed');
  });

  test('a transfer that never reaches warm-up still reports honestly', () {
    // This is the shape the broken probe produced: ~1.8 MB in 10s.
    final r = sipflixThroughputFrom(
      samples: evenTransfer(totalBytes: 1800000, durationUs: 10000000),
      warmupBytes: 2000000,
      burstWindowUs: 500000,
    )!;
    expect(r.sustainedMbps, closeTo(1.44, 0.1));
  });

  test('too few samples yields no verdict rather than a wrong one', () {
    expect(
      sipflixThroughputFrom(
          samples: const [(1000, 100)],
          warmupBytes: 2000000,
          burstWindowUs: 500000),
      isNull,
    );
  });

  test('burst catches a fast window inside an otherwise slow transfer', () {
    final samples = <(int, int)>[
      for (var i = 1; i <= 20; i++) (500000 * i, 50000 * i), // slow
      (10500000, 4000000), // 3 MB in 500ms = 48 Mbps
    ];
    final r = sipflixThroughputFrom(
      samples: samples,
      warmupBytes: 2000000,
      burstWindowUs: 500000,
    )!;
    expect(r.burstMbps, greaterThan(r.sustainedMbps));
  });
}
