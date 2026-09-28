import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../util/server_url.dart';
import 'sipflix_servers.dart';

/// How one server answered a sign-in attempt.
enum SipflixProbeOutcome {
  /// 200: the account exists here and the password is right.
  accepted,

  /// 401: unknown username or wrong password. Emby answers both the same way.
  rejected,

  /// 403: the account exists but is disabled.
  suspended,

  /// No answer from any route: timeouts, refused connections, 5xx, a proxy
  /// error page. Never read as "the account is not here".
  unreachable,
}

class SipflixProbeResult {
  final SipflixServerDef server;
  final SipflixProbeOutcome outcome;

  /// The route that answered. Null when [outcome] is unreachable.
  final String? routeUrl;

  /// The server's `AuthenticateByName` response, when [outcome] is accepted.
  final Map<String, dynamic>? authResult;

  const SipflixProbeResult({
    required this.server,
    required this.outcome,
    this.routeUrl,
    this.authResult,
  });

  String? get accessToken => authResult?['AccessToken'] as String?;
}

/// What sign-in should do with a set of probe results.
sealed class SipflixSignInVerdict {
  const SipflixSignInVerdict();
}

/// One or more servers took the credentials. One connects straight away;
/// several means the customer chooses.
class SipflixSignInAccepted extends SipflixSignInVerdict {
  final List<SipflixProbeResult> accepted;
  const SipflixSignInAccepted(this.accepted);
}

class SipflixSignInFailed extends SipflixSignInVerdict {
  final SipflixSignInFailure reason;
  const SipflixSignInFailed(this.reason);

  String get message => reason.message;
}

enum SipflixSignInFailure {
  suspended('This account is suspended. Contact support.'),
  notRecognised(
    'Username or password not recognised. Check both and try again. '
    'Still stuck? Contact support.',
  ),
  unreachable(
    "Couldn't reach the Sipflix servers. Check your internet connection and "
    'try again. Still stuck? Contact support.',
  );

  final String message;
  const SipflixSignInFailure(this.message);
}

/// One `AuthenticateByName` call. Returns the HTTP status and body, or a null
/// status when nothing answered at all.
typedef SipflixAuthCall = Future<({int? status, Map<String, dynamic>? body})>
    Function(String baseUrl, String username, String password);

/// Releases a token a probe obtained but sign-in did not use.
typedef SipflixLogoutCall = Future<void> Function(
    String baseUrl, String token);

/// Sipflix: asks every server whether it holds an account, in parallel.
///
/// The servers are the source of truth — no lookup service to keep in step.
/// Each server's routes are tried in order until one gives a real answer
/// (200/401/403); anything else moves on to the next route, and a server with
/// no route answering is [SipflixProbeOutcome.unreachable]. That is the
/// outage guard: a server that is down never counts as "account not here".
class SipflixAccountProbe {
  final SipflixAuthCall _auth;
  final SipflixLogoutCall _logout;

  SipflixAccountProbe({
    required SipflixAuthCall auth,
    required SipflixLogoutCall logout,
  })  : _auth = auth,
        _logout = logout;

  /// The live transport: plain Dio with this device's Emby identity, so a
  /// probe shows up as this box and not as a new device.
  factory SipflixAccountProbe.live(DeviceInfo deviceInfo) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 8),
      // Every status is an answer to classify, not an exception.
      validateStatus: (_) => true,
      responseType: ResponseType.json,
    ));
    Map<String, String> headers({String? token}) => {
          'X-Emby-Authorization': buildServerAuthorizationHeader(
            scheme: 'Emby',
            deviceInfo: deviceInfo,
            accessToken: token,
          ),
          'X-Emby-Token': ?token,
          'Accept': 'application/json',
        };
    return SipflixAccountProbe(
      auth: (baseUrl, username, password) async {
        try {
          final res = await dio.post<dynamic>(
            '${normalizeServerBaseUrl(baseUrl)}/emby/Users/AuthenticateByName',
            data: {'Username': username, 'Pw': password},
            options: Options(headers: headers()),
          );
          final data = res.data;
          return (
            status: res.statusCode,
            body: data is Map<String, dynamic> ? data : null,
          );
        } catch (_) {
          return (status: null, body: null);
        }
      },
      logout: (baseUrl, token) async {
        try {
          await dio.post<dynamic>(
            '${normalizeServerBaseUrl(baseUrl)}/emby/Sessions/Logout',
            options: Options(headers: headers(token: token)),
          );
        } catch (_) {}
      },
    );
  }

  /// Probe [servers] (all of them by default) in parallel. [preferredRoutes]
  /// maps a server key to the route to try first — the box's saved route, so a
  /// customer who picked Direct is not moved back to the default.
  Future<List<SipflixProbeResult>> probe(
    String username,
    String password, {
    List<SipflixServerDef> servers = SipflixServers.all,
    Map<String, String> preferredRoutes = const {},
  }) {
    return Future.wait([
      for (final def in servers)
        _probeOne(def, username, password, preferredRoutes[def.key]),
    ]);
  }

  Future<SipflixProbeResult> _probeOne(
    SipflixServerDef def,
    String username,
    String password,
    String? preferredRoute,
  ) async {
    for (final url in routeOrder(def, preferredRoute)) {
      final r = await _auth(url, username, password);
      final outcome = switch (r.status) {
        200 when r.body?['AccessToken'] is String =>
          SipflixProbeOutcome.accepted,
        401 => SipflixProbeOutcome.rejected,
        403 => SipflixProbeOutcome.suspended,
        _ => null,
      };
      if (outcome == null) continue; // no real answer: try the next route
      return SipflixProbeResult(
        server: def,
        outcome: outcome,
        routeUrl: url,
        authResult: outcome == SipflixProbeOutcome.accepted ? r.body : null,
      );
    }
    return SipflixProbeResult(
      server: def,
      outcome: SipflixProbeOutcome.unreachable,
    );
  }

  /// [def]'s routes with [preferred] first when it is one of them.
  static List<String> routeOrder(SipflixServerDef def, String? preferred) {
    final urls = def.routes.map((r) => r.url).toList();
    if (preferred == null) return urls;
    final p = normalizeServerBaseUrl(preferred);
    final i = urls.indexWhere((u) => normalizeServerBaseUrl(u) == p);
    if (i <= 0) return urls;
    return [urls[i], ...urls.take(i), ...urls.skip(i + 1)];
  }

  /// Turn probe results into what sign-in does next.
  ///
  /// Any acceptance wins. Otherwise an unreachable server blocks every other
  /// verdict, because the account may be on the server that did not answer —
  /// telling a moved customer "suspended" during an outage would be wrong. With
  /// every server answering, a 403 anywhere means the account is suspended.
  static SipflixSignInVerdict classify(List<SipflixProbeResult> results) {
    final accepted = results
        .where((r) => r.outcome == SipflixProbeOutcome.accepted)
        .toList();
    if (accepted.isNotEmpty) return SipflixSignInAccepted(accepted);
    if (results.any((r) => r.outcome == SipflixProbeOutcome.unreachable)) {
      return const SipflixSignInFailed(SipflixSignInFailure.unreachable);
    }
    if (results.any((r) => r.outcome == SipflixProbeOutcome.suspended)) {
      return const SipflixSignInFailed(SipflixSignInFailure.suspended);
    }
    return const SipflixSignInFailed(SipflixSignInFailure.notRecognised);
  }

  /// Log out the tokens of accepted probes that sign-in is not keeping, so a
  /// multi-server account does not collect ghost devices on every sign-in.
  Future<void> release(Iterable<SipflixProbeResult> unused) async {
    await Future.wait([
      for (final r in unused)
        if (r.accessToken != null && r.routeUrl != null)
          _logout(r.routeUrl!, r.accessToken!),
    ]);
  }
}
