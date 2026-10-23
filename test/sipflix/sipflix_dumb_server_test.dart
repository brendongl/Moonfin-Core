import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_account_probe.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';
import 'package:server_core/server_core.dart';

void main() {
  test('DUMB has a unique record and the Jellyfin client', () {
    final ids = SipflixServers.all.map((s) => s.recordId).toSet();
    expect(ids.length, SipflixServers.all.length);
    expect(SipflixServers.dumb.toRecord().serverType, ServerType.jellyfin);
    expect(SipflixServers.defForRef('https://s.sipflix.net/'), SipflixServers.dumb);
    expect(SipflixServers.defForId(SipflixServers.delta.recordId), SipflixServers.delta);
  });

  test('DUMB auth avoids Emby prefix; existing Emby routes keep it', () {
    expect(SipflixAccountProbe.apiRoot('https://s.sipflix.net/'), 'https://s.sipflix.net');
    for (final server in [SipflixServers.alphaV2, SipflixServers.delta, SipflixServers.iDuck]) {
      for (final route in server.routes) {
        expect(SipflixAccountProbe.apiRoot(route.url), '${route.url}/emby');
      }
    }
  });

  test('default probe offers both accepted Emby and Silo accounts', () async {
    final probe = SipflixAccountProbe(
      retryDelay: Duration.zero,
      auth: (url, username, password) async => (
        status: url == SipflixServers.dumb.defaultRoute.url || url == SipflixServers.alphaV2.defaultRoute.url ? 200 : 401,
        body: {'AccessToken': 'test-token', 'User': {'Id': 'test-user'}},
      ),
      logout: (_, _) async {},
    );
    final results = await probe.probe('test', 'test');
    final verdict = SipflixAccountProbe.classify(results) as SipflixSignInAccepted;
    expect(verdict.accepted.map((r) => r.server.key), ['AlphaV2', 'dumb']);
  });
}
