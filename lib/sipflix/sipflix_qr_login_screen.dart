import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../auth/models/server.dart';
import '../auth/repositories/server_repository.dart';
import '../ui/navigation/destinations.dart';
import 'sipflix_credential_vault.dart';
import 'sipflix_login_server.dart';
import 'sipflix_servers.dart';
import 'sipflix_sign_in.dart';

/// Sipflix: sign in by scanning a QR with your phone and typing credentials
/// there, instead of on the TV remote. The box hosts a small login web page;
/// submitted credentials authenticate the TV session.
class SipflixQrLoginScreen extends StatefulWidget {
  final String serverId;

  /// Sign in with the stored credentials straight away: the box's token was
  /// refused, most likely because the account moved to another server.
  final bool reprobe;

  const SipflixQrLoginScreen({
    super.key,
    required this.serverId,
    this.reprobe = false,
  });

  @override
  State<SipflixQrLoginScreen> createState() => _SipflixQrLoginScreenState();
}

class _SipflixQrLoginScreenState extends State<SipflixQrLoginScreen> {
  final _serverRepo = GetIt.instance<ServerRepository>();

  SipflixLoginServer? _httpServer;
  Server? _server;
  String? _url;
  String _status = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _httpServer?.stop();
    super.dispose();
  }

  Future<void> _init() async {
    await _serverRepo.loadStoredServers();
    final server = _serverRepo.getServer(widget.serverId);
    if (server == null) {
      if (mounted) context.go(Destinations.serverSelect);
      return;
    }
    final ip = await SipflixLoginServer.localIp();
    if (ip == null) {
      if (mounted) {
        setState(() {
          _server = server;
          _status = 'No network connection found.';
        });
      }
      return;
    }
    if (widget.reprobe) unawaited(_reprobe(server));
    final srv = SipflixLoginServer(
      serverName: 'Sipflix',
      onCredentials: (u, p) => _onCredentials(server, u, p),
    );
    try {
      await srv.start();
    } catch (_) {
      if (mounted) {
        setState(() {
          _server = server;
          _status = 'Could not start the phone-login helper.';
        });
      }
      return;
    }
    if (!mounted) {
      await srv.stop();
      return;
    }
    setState(() {
      _server = server;
      _httpServer = srv;
      _url = 'http://$ip:${SipflixLoginServer.port}';
    });
  }

  /// Sipflix: sign in on whichever server holds the account — every server
  /// is asked, so the customer never has to know which one they are on.
  Future<void> _onCredentials(
      Server server, String username, String password) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Signing in as $username…';
    });
    await _signIn(username, password);
  }

  /// The old server refused this box's token. Sign in again with the stored
  /// credentials wherever the account is now.
  Future<void> _reprobe(Server server) async {
    final creds = await SipflixCredentialVault().read();
    if (creds == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Checking your account…';
    });
    await _signIn(
      creds.username,
      creds.password,
      movedFromKey: SipflixServers.defForServer(server)?.key,
    );
  }

  Future<void> _signIn(
    String username,
    String password, {
    String? movedFromKey,
  }) async {
    String? error;
    try {
      error = await runSipflixSignIn(
        context,
        username: username,
        password: password,
        movedFromKey: movedFromKey,
      );
    } catch (_) {
      error = 'Sign-in failed. Please try again.';
    }
    if (!mounted) return;
    if (error == null) {
      await _httpServer?.stop();
      return;
    }
    setState(() {
      _busy = false;
      _status = error!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColorScheme.background,
              AppColorScheme.surfaceVariant,
              AppColorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo_and_text.png', height: 56),
                const SizedBox(height: 24),
                Text(
                  'Sign in with your phone',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _server == null
                      ? ''
                      : 'No more typing on the remote — scan to sign in to Sipflix',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                if (url != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: url,
                      version: QrVersions.auto,
                      size: 280,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '1. Scan with your phone camera, or open this address in its browser:',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    url,
                    style: TextStyle(
                      color: AppColorScheme.accent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '2. Type your username and password on your phone.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                    textAlign: TextAlign.center,
                  ),
                ] else if (_status.isEmpty) ...[
                  const CircularProgressIndicator(),
                ],
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy) ...[
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          _status,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  autofocus: true,
                  onPressed: () => context.go(
                      '${Destinations.login}?serverId=${widget.serverId}'),
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Type on the remote instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
