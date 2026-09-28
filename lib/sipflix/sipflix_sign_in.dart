import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/models/login_state.dart';
import '../auth/models/server.dart';
import '../auth/repositories/auth_repository.dart';
import '../auth/repositories/server_repository.dart';
import '../auth/repositories/session_repository.dart';
import '../auth/store/authentication_store.dart';
import '../auth/store/credential_store.dart';
import '../data/services/media_server_client_factory.dart';
import '../ui/navigation/app_router.dart';
import '../ui/navigation/destinations.dart';
import '../ui/widgets/adaptive/adaptive_dialog.dart';
import '../ui/widgets/overlay_sheet.dart';
import 'sipflix_account_probe.dart';
import 'sipflix_credential_vault.dart';
import 'sipflix_servers.dart';

/// Sipflix: signs the box in to whichever server holds the account.
///
/// The customer types a username and password once; every server is asked in
/// parallel ([SipflixAccountProbe]) and the box connects to the one that says
/// yes, or lets the customer choose when several do. A box holds one server at
/// a time — favourites and watch history live on the server — so connecting
/// drops every other Sipflix server record.
class SipflixSignIn {
  final SipflixAccountProbe _probe;
  final ServerRepository _serverRepo;
  final AuthenticationStore _authStore;
  final AuthRepository _authRepo;
  final SessionRepository _sessionRepo;
  final MediaServerClientFactory _clientFactory;
  final CredentialStore _credentialStore;
  final SipflixCredentialVault vault;

  SipflixSignIn({
    required SipflixAccountProbe probe,
    required ServerRepository serverRepo,
    required AuthenticationStore authStore,
    required AuthRepository authRepo,
    required SessionRepository sessionRepo,
    required MediaServerClientFactory clientFactory,
    required CredentialStore credentialStore,
    required this.vault,
  })  : _probe = probe,
        _serverRepo = serverRepo,
        _authStore = authStore,
        _authRepo = authRepo,
        _sessionRepo = sessionRepo,
        _clientFactory = clientFactory,
        _credentialStore = credentialStore;

  factory SipflixSignIn.fromGetIt() {
    final getIt = GetIt.instance;
    return SipflixSignIn(
      probe: SipflixAccountProbe.live(getIt<DeviceInfo>()),
      serverRepo: getIt<ServerRepository>(),
      authStore: getIt<AuthenticationStore>(),
      authRepo: getIt<AuthRepository>(),
      sessionRepo: getIt<SessionRepository>(),
      clientFactory: getIt<MediaServerClientFactory>(),
      credentialStore: getIt<CredentialStore>(),
      vault: SipflixCredentialVault(),
    );
  }

  /// The Sipflix server record this box holds now, if any.
  Server? get currentRecord => SipflixServers.findServer(
        _serverRepo.servers,
        preferId: _sessionRepo.activeServerId,
      );

  /// Ask [servers] whether they hold the account, trying each server's saved
  /// route first so a customer's route choice survives.
  Future<List<SipflixProbeResult>> probe(
    String username,
    String password, {
    List<SipflixServerDef> servers = SipflixServers.all,
  }) async {
    await _serverRepo.loadStoredServers();
    final preferred = <String, String>{};
    for (final s in _serverRepo.servers) {
      final def = SipflixServers.defForServer(s);
      if (def != null) preferred[def.key] = s.address;
    }
    return _probe.probe(
      username,
      password,
      servers: servers,
      preferredRoutes: preferred,
    );
  }

  /// Log out tokens from probes sign-in is not keeping.
  Future<void> release(Iterable<SipflixProbeResult> unused) =>
      _probe.release(unused);

  /// Make [chosen] this box's server and sign in with its probe token.
  /// Returns false when the session could not be started.
  Future<bool> connect(
    SipflixProbeResult chosen, {
    required String username,
    required String password,
  }) async {
    final def = chosen.server;
    final result = chosen.authResult;
    final route = chosen.routeUrl;
    if (result == null || route == null) return false;

    // Leaving a live session on another server: end it properly so that
    // server stops listing this box as signed in.
    final active = _sessionRepo.activeServerId;
    if (active != null && active != def.recordId) {
      await _sessionRepo.destroyCurrentSession();
    }

    // One server per box. Drop every other Sipflix record with its users and
    // token, so nothing can restore a session on the server the account left.
    await _serverRepo.loadStoredServers();
    for (final s in List.of(_serverRepo.servers)) {
      if (s.id == def.recordId) continue;
      if (!SipflixServers.isSipflixServerRecord(s)) continue;
      await _credentialStore.deleteToken(s.id);
      await _serverRepo.deleteServer(s.id);
    }

    final existing = _authStore.getServer(def.recordId);
    await _authStore.putServer(
      existing?.copyWith(name: def.name, address: route) ??
          def.toRecord(address: route),
    );
    await _serverRepo.loadStoredServers();

    final client = _clientFactory.getClient(
      serverId: def.recordId,
      serverType: ServerType.emby,
      baseUrl: route,
    );
    // A cached client may still point at another route of this server.
    client.baseUrl = route;

    final state = await _authRepo.adoptAuthResult(
      result: result,
      client: client,
      serverId: def.recordId,
      fallbackName: username,
    );
    if (state is! Authenticated) return false;

    final ok = await _sessionRepo.switchCurrentSession(
      serverId: state.serverId,
      userId: state.userId,
      username: username,
      password: password,
    );
    if (ok) await vault.save(username, password);
    return ok;
  }
}

/// Sipflix: the "your account has moved" notice, held until Home can show it.
/// Kept in SharedPreferences so a restart between sign-in and Home still
/// shows it once.
class SipflixMigrationNotice {
  SipflixMigrationNotice._();

  static const _key = 'sipflix_migrated_to_server';

  static String message(String serverName) =>
      'Your account has been migrated to $serverName. '
      "Favourites and watch history don't move between servers.";

  static Future<void> setPending(String serverName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, serverName);
  }

  static Future<String?> takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    if (name != null) await prefs.remove(_key);
    return name;
  }

  /// Show the notice if one is waiting. Dismissing it is all it asks.
  static Future<void> showIfPending(BuildContext context) async {
    final name = await takePending();
    if (name == null || !context.mounted) return;
    await showFocusRestoringDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Account moved'),
        content: Text(message(name)),
        actions: [
          adaptiveDialogAction(
            autofocus: true,
            isDefault: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Let the customer choose between servers that all accepted the account.
/// Null when they back out.
Future<SipflixProbeResult?> showSipflixServerPicker(
  BuildContext context,
  List<SipflixProbeResult> choices, {
  String? currentKey,
}) {
  return showFocusRestoringDialog<SipflixProbeResult>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: const Text('Choose a server'),
      content: const Text(
        'Your account is on more than one server. Favourites and watch '
        'history are kept separately on each.',
      ),
      actions: [
        for (final (i, c) in choices.indexed)
          adaptiveDialogAction(
            autofocus: i == 0,
            onPressed: () => Navigator.of(ctx).pop(c),
            child: Text(
              c.server.key == currentKey
                  ? '${c.server.name} (current)'
                  : c.server.name,
            ),
          ),
      ],
    ),
  );
}

/// Sign in with [username] and [password] on whichever server holds the
/// account, and go Home. Returns null on success, or the message to show.
///
/// [movedFromKey] is the server whose token was just cut off. Landing
/// anywhere else leaves the "account migrated" notice for Home.
Future<String?> runSipflixSignIn(
  BuildContext context, {
  required String username,
  required String password,
  String? movedFromKey,
  SipflixSignIn? signIn,
}) async {
  final flow = signIn ?? SipflixSignIn.fromGetIt();
  final results = await flow.probe(username, password);
  final verdict = SipflixAccountProbe.classify(results);

  switch (verdict) {
    case SipflixSignInFailed():
      return verdict.message;
    case SipflixSignInAccepted(:final accepted):
      SipflixProbeResult? chosen;
      if (accepted.length == 1) {
        chosen = accepted.single;
      } else {
        if (!context.mounted) {
          await flow.release(accepted);
          return null;
        }
        chosen = await showSipflixServerPicker(context, accepted);
      }
      if (chosen == null) {
        await flow.release(accepted);
        return 'Choose a server to continue.';
      }
      await flow.release(accepted.where((r) => r != chosen));
      final ok = await flow.connect(
        chosen,
        username: username,
        password: password,
      );
      if (!ok) return 'Sign-in failed. Please try again.';
      if (movedFromKey != null && chosen.server.key != movedFromKey) {
        await SipflixMigrationNotice.setPending(chosen.server.name);
      }
      appRouter.go(Destinations.home);
      return null;
  }
}

/// Settings > Switch server. Moves a multi-server account to another server,
/// after warning that favourites and watch history stay behind.
Future<void> runSipflixSwitchServer(BuildContext context) async {
  final flow = SipflixSignIn.fromGetIt();
  final current = flow.currentRecord;
  final currentDef =
      current == null ? null : SipflixServers.defForServer(current);

  final confirmed = await showFocusRestoringDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: const Text('Switch server?'),
      content: const Text(
        "Favourites and watch history don't move between servers.",
      ),
      actions: [
        adaptiveDialogAction(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        adaptiveDialogAction(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final creds = await flow.vault.read();
  if (creds == null || currentDef == null) {
    // Nothing stored to ask the other servers with: sign in again, which asks
    // every server and offers the choice.
    await GetIt.instance<SessionRepository>().destroyCurrentSession();
    appRouter.go(
      '${Destinations.qrLogin}?serverId=${current?.id ?? SipflixServers.serverId}',
    );
    return;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    const SnackBar(content: Text('Checking which servers your account is on…')),
  );

  // Never probe the current server: a fresh login there could replace the
  // token this session is running on. It is known to hold the account.
  final others = [
    for (final d in SipflixServers.all)
      if (d.key != currentDef.key) d,
  ];
  final results = await flow.probe(
    creds.username,
    creds.password,
    servers: others,
  );
  final accepted = results
      .where((r) => r.outcome == SipflixProbeOutcome.accepted)
      .toList();
  if (!context.mounted) {
    await flow.release(accepted);
    return;
  }

  if (accepted.isEmpty) {
    final anyDown =
        results.any((r) => r.outcome == SipflixProbeOutcome.unreachable);
    messenger?.showSnackBar(SnackBar(
      content: Text(anyDown
          ? SipflixSignInFailure.unreachable.message
          : 'Your account is only on ${currentDef.name}.'),
    ));
    return;
  }

  final chosen = await showSipflixServerPicker(
    context,
    [
      SipflixProbeResult(
        server: currentDef,
        outcome: SipflixProbeOutcome.accepted,
      ),
      ...accepted,
    ],
    currentKey: currentDef.key,
  );
  if (chosen == null || chosen.server.key == currentDef.key) {
    await flow.release(accepted);
    return;
  }
  await flow.release(accepted.where((r) => r != chosen));
  final ok = await flow.connect(
    chosen,
    username: creds.username,
    password: creds.password,
  );
  if (!context.mounted) return;
  if (!ok) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Switching failed. Please try again.')),
    );
    return;
  }
  appRouter.go(Destinations.home);
}
