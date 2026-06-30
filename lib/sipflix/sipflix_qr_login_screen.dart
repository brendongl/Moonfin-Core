import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../auth/models/login_state.dart';
import '../auth/models/server.dart';
import '../auth/repositories/auth_repository.dart';
import '../auth/repositories/server_repository.dart';
import '../auth/repositories/session_repository.dart';
import '../data/services/media_server_client_factory.dart';
import '../ui/navigation/destinations.dart';
import 'sipflix_login_server.dart';

/// Sipflix: sign in by scanning a QR with your phone and typing credentials
/// there, instead of on the TV remote. The box hosts a small login web page;
/// submitted credentials authenticate the TV session.
class SipflixQrLoginScreen extends StatefulWidget {
  final String serverId;
  const SipflixQrLoginScreen({super.key, required this.serverId});

  @override
  State<SipflixQrLoginScreen> createState() => _SipflixQrLoginScreenState();
}

class _SipflixQrLoginScreenState extends State<SipflixQrLoginScreen> {
  final _serverRepo = GetIt.instance<ServerRepository>();
  final _authRepo = GetIt.instance<AuthRepository>();
  final _sessionRepo = GetIt.instance<SessionRepository>();
  final _clientFactory = GetIt.instance<MediaServerClientFactory>();

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
    final srv = SipflixLoginServer(
      serverName: server.name,
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

  Future<void> _onCredentials(
      Server server, String username, String password) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Signing in as $username…';
    });
    final client = _clientFactory.getClient(
      serverId: server.id,
      serverType: server.serverType,
      baseUrl: server.address,
    );
    try {
      final result = await _authRepo.authenticate(
        client: client,
        serverId: server.id,
        username: username,
        password: password,
      );
      if (!mounted) return;
      if (result is Authenticated) {
        final ok = await _sessionRepo.switchCurrentSession(
          serverId: result.serverId,
          userId: result.userId,
          username: username,
          password: password,
        );
        if (!mounted) return;
        if (ok) {
          await _httpServer?.stop();
          if (mounted) context.go(Destinations.home);
          return;
        }
        setState(() {
          _busy = false;
          _status = 'Login failed — please try again on your phone.';
        });
      } else {
        setState(() {
          _busy = false;
          _status = 'Login failed — check the username and password.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Login error — please try again.';
      });
    }
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
                      : 'No more typing on the remote — scan to sign in to ${_server!.name}',
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
