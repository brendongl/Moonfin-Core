import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials stay in encrypted platform storage, independently per server.
/// The active pointer preserves read() for older callers. Scoped reads never
/// borrow another server's password. Legacy single-account installs migrate
/// their old pair when the first server-scoped read identifies its owner.
class SipflixCredentialVault {
  static const _usernameKey = 'sipflix_account_username';
  static const _passwordKey = 'sipflix_account_password';
  static const _activeKey = 'sipflix_account_active_server';
  static const _prefix = 'sipflix_account_server_';
  final FlutterSecureStorage _storage;

  SipflixCredentialVault([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  String _key(String serverId) => '$_prefix${Uri.encodeComponent(serverId)}';

  Future<void> save(
    String username,
    String password, {
    String? serverId,
    bool makeActive = true,
  }) async {
    try {
      if (serverId != null) {
        // One encrypted write keeps username/password updates atomic.
        await _storage.write(
          key: _key(serverId),
          value: jsonEncode({'username': username, 'password': password}),
        );
        if (makeActive) await _storage.write(key: _activeKey, value: serverId);
        // Do not keep a global password which could be reused for a different
        // server when one scoped record is absent.
        await _storage.delete(key: _usernameKey);
        await _storage.delete(key: _passwordKey);
      } else {
        final active = await _storage.read(key: _activeKey);
        if (active != null) {
          await save(username, password, serverId: active);
        } else {
          await _storage.write(key: _usernameKey, value: username);
          await _storage.write(key: _passwordKey, value: password);
        }
      }
    } on Exception catch (_) {}
  }

  Future<void> activate(String serverId) async {
    try {
      await _storage.write(key: _activeKey, value: serverId);
    } on Exception catch (_) {}
  }

  Future<({String username, String password})?> read({String? serverId}) async {
    try {
      final active = await _storage.read(key: _activeKey);
      final owner = serverId ?? active;
      if (owner != null) {
        final raw = await _storage.read(key: _key(owner));
        if (raw != null) {
          final data = jsonDecode(raw);
          if (data is Map &&
              data['username'] is String &&
              (data['username'] as String).isNotEmpty &&
              data['password'] is String) {
            return (
              username: data['username'] as String,
              password: data['password'] as String,
            );
          }
          return null;
        }
        if (active != null) return null;
      }
      final username = await _storage.read(key: _usernameKey);
      final password = await _storage.read(key: _passwordKey);
      if (username == null || username.isEmpty || password == null) return null;
      if (owner != null) await save(username, password, serverId: owner);
      return (username: username, password: password);
    } on Exception catch (_) {
      return null;
    }
  }

  /// A deliberate single-account sign-out forgets only that server.
  Future<void> clear({String? serverId}) async {
    try {
      final active = await _storage.read(key: _activeKey);
      final owner = serverId ?? active;
      if (owner != null) await _storage.delete(key: _key(owner));
      if (serverId == null || owner == active) {
        await _storage.delete(key: _activeKey);
        await _storage.delete(key: _usernameKey);
        await _storage.delete(key: _passwordKey);
      }
    } on Exception catch (_) {}
  }

  Future<void> clearAll() async {
    try {
      final values = await _storage.readAll();
      for (final key in values.keys.toList()) {
        if (key.startsWith(_prefix) ||
            key == _activeKey ||
            key == _usernameKey ||
            key == _passwordKey) {
          await _storage.delete(key: key);
        }
      }
    } on Exception catch (_) {}
  }
}
