import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sipflix: the box's own username and password, kept in Android's encrypted
/// storage beside the access token.
///
/// Needed for one thing: when an admin moves an account to another server the
/// old server cuts the box's token off (401), and the app signs in to the new
/// server with these instead of sending the customer back to the login page.
///
/// Every call answers rather than throwing, like [CredentialStoreImpl]: losing
/// the stored copy costs one manual sign-in, never a crash.
class SipflixCredentialVault {
  static const _usernameKey = 'sipflix_account_username';
  static const _passwordKey = 'sipflix_account_password';

  final FlutterSecureStorage _storage;

  SipflixCredentialVault([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> save(String username, String password) async {
    try {
      await _storage.write(key: _usernameKey, value: username);
      await _storage.write(key: _passwordKey, value: password);
    } on Exception catch (_) {}
  }

  /// The stored credentials, or null when there are none.
  Future<({String username, String password})?> read() async {
    try {
      final username = await _storage.read(key: _usernameKey);
      final password = await _storage.read(key: _passwordKey);
      if (username == null || username.isEmpty || password == null) {
        return null;
      }
      return (username: username, password: password);
    } on Exception catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _usernameKey);
      await _storage.delete(key: _passwordKey);
    } on Exception catch (_) {}
  }
}
