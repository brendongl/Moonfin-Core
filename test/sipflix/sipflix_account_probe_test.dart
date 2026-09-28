import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_account_probe.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

// Sign-in asks every server at once. These pin down how answers become a
// verdict — and that an outage never reads as "account not here".
void main() {
  const ok = {'AccessToken': 'tok', 'User': {'Id': 'u1', 'Name': 'max'}};

  /// A fake transport: [answers] maps a route URL to its status (null = no
  /// answer at all). Records every call.
  ({SipflixAccountProbe probe, List<String> calls, List<String> logouts})
      fake(Map<String, int?> answers) {
    final calls = <String>[];
    final logouts = <String>[];
    final probe = SipflixAccountProbe(
      auth: (url, user, pw) async {
        calls.add(url);
        final status = answers[url];
        return (status: status, body: status == 200 ? ok : null);
      },
      logout: (url, token) async => logouts.add(url),
    );
    return (probe: probe, calls: calls, logouts: logouts);
  }

  String first(SipflixServerDef d) => d.routes.first.url;
  String second(SipflixServerDef d) => d.routes[1].url;

  final a = SipflixServers.alphaV2;
  final d = SipflixServers.delta;
  final i = SipflixServers.iDuck;

  group('probe', () {
    test('one server accepts: that server, with the route that answered',
        () async {
      final f = fake({first(a): 401, first(d): 200, first(i): 401});
      final results = await f.probe.probe('max', 'pw');
      final verdict = SipflixAccountProbe.classify(results);
      expect(verdict, isA<SipflixSignInAccepted>());
      final accepted = (verdict as SipflixSignInAccepted).accepted;
      expect(accepted.single.server.key, 'emby2');
      expect(accepted.single.routeUrl, first(d));
      expect(accepted.single.accessToken, 'tok');
    });

    test('a dead route falls through to the next route of that server',
        () async {
      final f = fake({
        first(a): null,
        second(a): 200,
        first(d): 401,
        first(i): 401,
      });
      final results = await f.probe.probe('max', 'pw');
      final alpha = results.firstWhere((r) => r.server.key == 'AlphaV2');
      expect(alpha.outcome, SipflixProbeOutcome.accepted);
      expect(alpha.routeUrl, second(a));
    });

    test('a 5xx is no answer, never a rejection', () async {
      final f = fake({
        for (final r in d.routes) r.url: 502,
        first(a): 401,
        first(i): 401,
      });
      final results = await f.probe.probe('max', 'pw');
      expect(results.firstWhere((r) => r.server.key == 'emby2').outcome,
          SipflixProbeOutcome.unreachable);
    });

    test('tries the saved route first', () async {
      final f = fake({
        for (final dd in SipflixServers.all)
          for (final r in dd.routes) r.url: 401,
      });
      await f.probe.probe('max', 'pw',
          preferredRoutes: {'AlphaV2': SipflixServers.directUrl});
      expect(f.calls, contains(SipflixServers.directUrl));
      expect(f.calls, isNot(contains(SipflixServers.cdnUrl)));
    });

    test('release logs out only the tokens handed to it', () async {
      final f = fake({first(a): 200, first(d): 200, first(i): 401});
      final results = await f.probe.probe('max', 'pw');
      final keep = results.firstWhere((r) => r.server.key == 'AlphaV2');
      await f.probe.release(results.where(
          (r) => r != keep && r.outcome == SipflixProbeOutcome.accepted));
      expect(f.logouts, [first(d)]);
    });
  });

  group('classify', () {
    SipflixProbeResult r(SipflixServerDef def, SipflixProbeOutcome o) =>
        SipflixProbeResult(server: def, outcome: o);
    const acc = SipflixProbeOutcome.accepted;
    const rej = SipflixProbeOutcome.rejected;
    const sus = SipflixProbeOutcome.suspended;
    const down = SipflixProbeOutcome.unreachable;

    SipflixSignInFailure failure(List<SipflixProbeResult> results) =>
        (SipflixAccountProbe.classify(results) as SipflixSignInFailed).reason;

    test('several accept: the customer chooses', () {
      final v = SipflixAccountProbe.classify(
          [r(a, acc), r(d, acc), r(i, rej)]);
      expect((v as SipflixSignInAccepted).accepted.length, 2);
    });

    test('an acceptance wins over an outage elsewhere', () {
      final v =
          SipflixAccountProbe.classify([r(a, down), r(d, acc), r(i, rej)]);
      expect(v, isA<SipflixSignInAccepted>());
    });

    test('all 403: suspended', () {
      expect(failure([r(a, sus), r(d, sus), r(i, sus)]),
          SipflixSignInFailure.suspended);
    });

    test('disabled on one, unknown elsewhere: suspended', () {
      expect(failure([r(a, sus), r(d, rej), r(i, rej)]),
          SipflixSignInFailure.suspended);
    });

    test('all 401: not recognised', () {
      expect(failure([r(a, rej), r(d, rej), r(i, rej)]),
          SipflixSignInFailure.notRecognised);
    });

    test('a server down blocks "suspended" and "not recognised"', () {
      expect(failure([r(a, sus), r(d, down), r(i, rej)]),
          SipflixSignInFailure.unreachable);
      expect(failure([r(a, rej), r(d, rej), r(i, down)]),
          SipflixSignInFailure.unreachable);
    });

    test('messages are the agreed wording', () {
      expect(SipflixSignInFailure.suspended.message,
          'This account is suspended. Contact support.');
      expect(
        SipflixSignInFailure.notRecognised.message,
        'Username or password not recognised. Check both and try again. '
        'Still stuck? Contact support.',
      );
    });
  });

  test('routeOrder puts the preferred route first and keeps the rest', () {
    expect(
      SipflixAccountProbe.routeOrder(a, SipflixServers.directUrl),
      [SipflixServers.directUrl, SipflixServers.cdnUrl, SipflixServers.cdn2Url],
    );
    expect(SipflixAccountProbe.routeOrder(a, 'https://other.example'),
        a.routes.map((r) => r.url).toList());
  });
}
