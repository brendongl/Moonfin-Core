import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_bandwidth_probe.dart';
import 'package:moonfin/sipflix/sipflix_bitrate_watchdog.dart';
import 'package:moonfin/sipflix/sipflix_preflight.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

// Stream Preflight's decision: DirectPlay on the fastest route that sustains
// the file's bitrate (with headroom), else the best route capped to a tier the
// link proved it can carry.
void main() {
  const cdn = SipflixRouteDef(id: 'cdn1', label: 'CDN 1', url: 'https://c');
  const direct = SipflixRouteDef(id: 'direct', label: 'Direct', url: 'https://d');

  ({SipflixRouteDef route, SipflixRouteMeasurement m}) r(
    SipflixRouteDef route,
    double sustained, {
    double? burst,
  }) =>
      (
        route: route,
        m: SipflixRouteMeasurement(
          burstMbps: burst ?? sustained * 1.5,
          sustainedMbps: sustained,
        ),
      );

  SipflixPreflightDecision decide(
    List<({SipflixRouteDef route, SipflixRouteMeasurement m})> results,
    double required,
  ) =>
      SipflixPreflightController.decide(
        results: results,
        requiredMbps: required,
        tiers: SipflixBitrateWatchdog.tiers,
      );

  test('fastest sustaining route wins and direct-plays uncapped', () {
    final d = decide([r(cdn, 30), r(direct, 55)], 40.8); // 34 Mbps file * 1.2
    expect(d.route.id, 'direct');
    expect(d.direct, isTrue);
    expect(d.capMbps, isNull);
  });

  test('slower route that still sustains the file is NOT preferred', () {
    final d = decide([r(cdn, 80), r(direct, 45)], 40.8);
    expect(d.route.id, 'cdn1');
    expect(d.capMbps, isNull);
  });

  test('neither route sustains: best route, capped to a provable tier', () {
    // Best sustained 12 -> budget 9.6 -> highest tier <= 9.6 is 8.
    final d = decide([r(cdn, 12), r(direct, 7)], 40.8);
    expect(d.route.id, 'cdn1');
    expect(d.direct, isFalse);
    expect(d.capMbps, 8);
  });

  test('very slow link still gets the floor tier, never zero', () {
    final d = decide([r(cdn, 1.5), r(direct, 0.9)], 40.8);
    expect(d.capMbps, SipflixBitrateWatchdog.tiers.last);
  });

  test('single surviving route is used even when the other failed', () {
    final d = decide([r(direct, 25)], 12);
    expect(d.route.id, 'direct');
    expect(d.capMbps, isNull);
  });

  test('exact boundary counts as sustaining', () {
    final d = decide([r(cdn, 40.8)], 40.8);
    expect(d.direct, isTrue);
  });
}
