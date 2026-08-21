import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_preflight.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

// Preflight probes routes one at a time, each capped at `perRouteCap`. The
// overall budget therefore has to clear the worst case for EVERY route, or the
// last route in the list is never reached: with a hardcoded 26s and three
// routes, a slow CDN 1 ate the budget and Direct was never measured.
void main() {
  test('the budget clears a worst-case probe of every route', () {
    final worstCase = SipflixPreflightController.perRouteCap *
        SipflixServers.routeChoices.length;
    expect(
      SipflixPreflightController.overallTimeout,
      greaterThan(worstCase),
      reason: 'every route must be probeable before the preflight gives up',
    );
  });

  test('the budget tracks the route list rather than being a constant', () {
    // Two routes' worth of budget would not have covered today's three.
    final twoRouteBudget = SipflixPreflightController.perRouteCap * 2 +
        const Duration(seconds: 6);
    expect(SipflixServers.routeChoices.length, greaterThan(2));
    expect(
      SipflixPreflightController.overallTimeout,
      greaterThan(twoRouteBudget),
    );
  });
}
