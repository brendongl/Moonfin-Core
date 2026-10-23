import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/models/login_state.dart';
import '../auth/models/server.dart';
import '../auth/models/user.dart';
import '../auth/repositories/auth_repository.dart';
import '../auth/repositories/server_repository.dart';
import '../auth/repositories/session_repository.dart';
import '../auth/store/authentication_store.dart';
import '../ui/navigation/app_router.dart';
import '../ui/navigation/destinations.dart';
import '../ui/widgets/adaptive/adaptive_dialog.dart';
import '../ui/widgets/overlay_sheet.dart';
import 'sipflix_account_probe.dart';
import 'sipflix_credential_vault.dart';
import 'sipflix_servers.dart';
import 'sipflix_route_selector.dart';
import 'sipflix_error_reporter.dart';

/// Sipflix: signs the box in to whichever server holds the account.
///
/// The customer types a username and password once; every server is asked in
/// parallel ([SipflixAccountProbe]) and the box connects to the one that says
/// yes, or lets the customer choose when several do. One session is active,
/// while the other servers retain their own saved identities and credentials.
class SipflixSavedAccount {
  const SipflixSavedAccount(this.server, this.user);
  final Server server;
  final PrivateUser user;
}

class SipflixSignIn {
  final SipflixAccountProbe _probe;
  final ServerRepository _serverRepo;
  final AuthenticationStore _authStore;
  final AuthRepository _authRepo;
  final SessionRepository _sessionRepo;
  final SipflixCredentialVault vault;

  SipflixSignIn({
    required SipflixAccountProbe probe,
    required ServerRepository serverRepo,
    required AuthenticationStore authStore,
    required AuthRepository authRepo,
    required SessionRepository sessionRepo,
    required this.vault,
  }) : _probe = probe,
       _serverRepo = serverRepo,
       _authStore = authStore,
       _authRepo = authRepo,
       _sessionRepo = sessionRepo;

  factory SipflixSignIn.fromGetIt() {
    final getIt = GetIt.instance;
    return SipflixSignIn(
      probe: SipflixAccountProbe.live(getIt<DeviceInfo>()),
      serverRepo: getIt<ServerRepository>(),
      authStore: getIt<AuthenticationStore>(),
      authRepo: getIt<AuthRepository>(),
      sessionRepo: getIt<SessionRepository>(),
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

  /// Save another accepted account without changing the active session.
  Future<bool> remember(
    SipflixProbeResult accepted, {
    required String username,
    required String password,
  }) async {
    final active = _sessionRepo.activeServerId;
    if (active != null)
      await vault.read(serverId: active); // Bind legacy credentials first.
    final def = accepted.server;
    final route = accepted.routeUrl;
    final result = accepted.authResult;
    if (route == null || result == null) return false;
    final existing = _authStore.getServer(def.recordId);
    await _authStore.putServer(
      existing?.copyWith(name: def.name, address: route) ??
          def.toRecord(address: route),
    );
    final state = await _authRepo.storeAuthResult(
      result: result,
      serverId: def.recordId,
      fallbackName: username,
    );
    if (state is! Authenticated) return false;
    await vault.save(
      username,
      password,
      serverId: def.recordId,
      makeActive: false,
    );
    return true;
  }

  List<SipflixSavedAccount> get savedAccounts => [
    for (final server in _authStore.getServers())
      if (SipflixServers.isSipflixServerRecord(server))
        for (final user in _authStore.getUsers(server.id))
          if (user.accessToken.isNotEmpty) SipflixSavedAccount(server, user),
  ];

  /// Reuse the selected server's own token, validating it before session setup.
  /// No password is sent to other servers and no saved account is deleted.
  Future<bool> connectSaved(SipflixSavedAccount account) async {
    await _serverRepo.loadStoredServers();
    final credentials = await vault.read(serverId: account.server.id);
    final matching = credentials?.username == account.user.name;
    final ok = await _sessionRepo.switchCurrentSession(
      serverId: account.server.id,
      userId: account.user.id,
      username: matching ? credentials!.username : null,
      password: matching ? credentials!.password : null,
      validateToken: true,
    );
    if (ok) {
      await vault.activate(account.server.id);
      if (GetIt.instance.isRegistered<SipflixRouteSelector>()) {
        unawaited(
          GetIt.instance<SipflixRouteSelector>().refreshIfStale(force: true),
        );
      }
    }
    return ok;
  }

  /// Make [chosen] this box's server and sign in with its probe token.
  /// Returns false when the session could not be started.
  Future<bool> connect(
    SipflixProbeResult chosen, {
    required String username,
    required String password,
  }) async {
    final active = _sessionRepo.activeServerId;
    if (active != null)
      await vault.read(serverId: active); // Preserve a legacy active account.
    final def = chosen.server;
    final result = chosen.authResult;
    final route = chosen.routeUrl;
    if (result == null || route == null) return false;

    // Switching keeps saved identities. SessionRepository stops playback and
    // disconnects the old socket without deleting the other server's login.
    final existing = _authStore.getServer(def.recordId);
    await _authStore.putServer(
      existing?.copyWith(name: def.name, address: route) ??
          def.toRecord(address: route),
    );
    await _serverRepo.loadStoredServers();

    final state = await _authRepo.storeAuthResult(
      result: result,
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
    if (ok) {
      await vault.save(username, password, serverId: def.recordId);
      if (GetIt.instance.isRegistered<SipflixRouteSelector>()) {
        unawaited(
          GetIt.instance<SipflixRouteSelector>().refreshIfStale(force: true),
        );
      }
    }
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
  bool Function()? isCancelled,
  Future<SipflixProbeResult?> Function(BuildContext, List<SipflixProbeResult>)?
  pickServer,
}) async {
  final flow = signIn ?? SipflixSignIn.fromGetIt();
  bool cancelled() => !context.mounted || (isCancelled?.call() ?? false);
  const closed = 'The TV sign-in attempt ended. Open a new QR code.';
  if (cancelled()) return closed;
  final results = await flow.probe(username, password);
  final verdict = SipflixAccountProbe.classify(results);

  switch (verdict) {
    case SipflixSignInFailed():
      SipflixErrorReporter.capture(
        'sign-in',
        verdict.message,
        code: verdict.reason.name,
      );
      return verdict.message;
    case SipflixSignInAccepted(:final accepted):
      final pending = accepted.toSet();
      if (cancelled()) {
        await flow.release(pending);
        return closed;
      }
      SipflixProbeResult? chosen;
      if (accepted.length == 1) {
        chosen = accepted.single;
      } else {
        if (!context.mounted) {
          await flow.release(accepted);
          return 'The TV sign-in screen has closed. Scan the new QR code.';
        }
        chosen = await (pickServer ?? showSipflixServerPicker)(
          context,
          accepted,
        );
      }
      if (chosen == null) {
        await flow.release(accepted);
        return 'Choose a server to continue.';
      }
      if (cancelled()) {
        await flow.release(pending);
        return closed;
      }
      for (final other in accepted.where((r) => r != chosen)) {
        if (!await flow.remember(
          other,
          username: username,
          password: password,
        )) {
          await flow.release([other]);
        }
        pending.remove(other);
        if (cancelled()) {
          await flow.release(pending);
          return closed;
        }
      }
      if (cancelled()) {
        await flow.release(pending);
        return closed;
      }
      final ok = await flow.connect(
        chosen,
        username: username,
        password: password,
      );
      if (!ok) return 'Sign-in failed. Please try again.';
      // Connect may have completed while the screen/attempt was cancelled.
      // Do not navigate or acknowledge that obsolete attempt. The established
      // session owns its token now, so do not log it out here.
      if (cancelled()) return closed;
      if (movedFromKey != null && chosen.server.key != movedFromKey) {
        await SipflixMigrationNotice.setPending(chosen.server.name);
      }
      if (cancelled()) return closed;
      appRouter.go(Destinations.home);
      return null;
  }
}

/// Settings > Switch server. Moves a multi-server account to another server,
/// after warning that favourites and watch history stay behind.
Future<void> runSipflixSwitchServer(BuildContext context) async {
  final flow = SipflixSignIn.fromGetIt();
  final current = flow.currentRecord;
  final currentDef = current == null
      ? null
      : SipflixServers.defForServer(current);

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
  if (confirmed != true) return;

  // The settings panel this started from closes around the dialog, taking its
  // context with it; everything after the confirmation runs on the app's
  // root navigator instead.
  final root = appRouter.routerDelegate.navigatorKey.currentContext;
  if (root == null || !root.mounted) return;

  final saved = flow.savedAccounts;
  if (saved.isNotEmpty) {
    var addAccount = false;
    final picked = await showFocusRestoringDialog<SipflixSavedAccount>(
      context: root,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Choose an account'),
        content: const Text(
          'Each server keeps its own favourites and watch history.',
        ),
        actions: [
          for (final account in saved)
            adaptiveDialogAction(
              onPressed: () => Navigator.of(ctx).pop(account),
              child: Text('${account.server.name} — ${account.user.name}'),
            ),
          adaptiveDialogAction(
            onPressed: () {
              addAccount = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('Sign in to another account'),
          ),
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (addAccount) {
      appRouter.go(
        '${Destinations.qrLogin}?serverId=${current?.id ?? SipflixServers.serverId}',
      );
      return;
    }
    if (picked == null) return;
    if (await flow.connectSaved(picked)) {
      appRouter.go(Destinations.home);
    } else if (root.mounted) {
      ScaffoldMessenger.maybeOf(root)?.showSnackBar(
        const SnackBar(
          content: Text('Could not switch accounts. Please sign in again.'),
        ),
      );
    }
    return;
  }

  final creds = await flow.vault.read(serverId: current?.id);
  if (creds == null || currentDef == null) {
    // Nothing stored to ask the other servers with: sign in again, which asks
    // every server and offers the choice.
    appRouter.go(
      '${Destinations.qrLogin}?serverId=${current?.id ?? SipflixServers.serverId}',
    );
    return;
  }

  if (!root.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(root);
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
  if (!root.mounted) {
    await flow.release(accepted);
    return;
  }

  if (accepted.isEmpty) {
    final anyDown = results.any(
      (r) => r.outcome == SipflixProbeOutcome.unreachable,
    );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          anyDown
              ? SipflixSignInFailure.unreachable.message
              : 'Your account is only on ${currentDef.name}.',
        ),
      ),
    );
    return;
  }

  final chosen = await showSipflixServerPicker(root, [
    SipflixProbeResult(
      server: currentDef,
      outcome: SipflixProbeOutcome.accepted,
    ),
    ...accepted,
  ], currentKey: currentDef.key);
  if (chosen == null || chosen.server.key == currentDef.key) {
    await flow.release(accepted);
    return;
  }
  for (final other in accepted.where((r) => r != chosen)) {
    if (!await flow.remember(
      other,
      username: creds.username,
      password: creds.password,
    )) {
      await flow.release([other]);
    }
  }
  final ok = await flow.connect(
    chosen,
    username: creds.username,
    password: creds.password,
  );
  if (!ok) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Switching failed. Please try again.')),
    );
    return;
  }
  appRouter.go(Destinations.home);
}
