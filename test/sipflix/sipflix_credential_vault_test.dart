import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_credential_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SipflixCredentialVault vault;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    vault = SipflixCredentialVault();
  });
  test(
    'different Emby and Silo credentials survive repeated switches',
    () async {
      await vault.save('emby-test', 'emby-test-password', serverId: 'alpha');
      await vault.save('silo-test', 'silo-test-password', serverId: 'silo');
      expect((await vault.read())?.username, 'silo-test');
      await vault.activate('alpha');
      expect((await vault.read())?.password, 'emby-test-password');
      expect((await vault.read(serverId: 'silo'))?.username, 'silo-test');
      await vault.activate('silo');
      expect((await vault.read())?.password, 'silo-test-password');
    },
  );
  test('background remember does not change active credentials', () async {
    await vault.save('alpha', 'alpha-password', serverId: 'alpha');
    await vault.save(
      'silo',
      'silo-password',
      serverId: 'silo',
      makeActive: false,
    );
    expect((await vault.read())?.username, 'alpha');
    expect((await vault.read(serverId: 'silo'))?.username, 'silo');
  });
  test(
    'missing scoped credentials cannot borrow another server password',
    () async {
      await vault.save('alpha', 'alpha-password', serverId: 'alpha');
      expect(await vault.read(serverId: 'silo'), isNull);
      await vault.activate('silo');
      expect(await vault.read(), isNull);
      expect((await vault.read(serverId: 'alpha'))?.username, 'alpha');
    },
  );
  test(
    'legacy credentials bind once and never leak to a second server',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'sipflix_account_username': 'legacy-test',
        'sipflix_account_password': 'legacy-password',
      });
      expect((await vault.read(serverId: 'alpha'))?.username, 'legacy-test');
      expect(await vault.read(serverId: 'silo'), isNull);
      expect(
        (await vault.read(serverId: 'alpha'))?.password,
        'legacy-password',
      );
      expect(
        await const FlutterSecureStorage().read(
          key: 'sipflix_account_password',
        ),
        isNull,
      );
    },
  );
  test('single signout retains secondary credentials', () async {
    await vault.save('alpha', 'a', serverId: 'alpha');
    await vault.save('silo', 'b', serverId: 'silo');
    await vault.clear();
    expect(await vault.read(serverId: 'silo'), isNull);
    expect((await vault.read(serverId: 'alpha'))?.password, 'a');
  });
  test('scoped clear of secondary leaves active pointer intact', () async {
    await vault.save('silo', 'b', serverId: 'silo');
    await vault.save('alpha', 'a', serverId: 'alpha');
    await vault.clear(serverId: 'silo');
    expect((await vault.read())?.username, 'alpha');
  });
  test('sign out all removes Sipflix credentials only', () async {
    await const FlutterSecureStorage().write(key: 'unrelated', value: 'keep');
    await vault.save('alpha', 'a', serverId: 'alpha');
    await vault.save('silo', 'b', serverId: 'silo');
    await vault.clearAll();
    expect(await vault.read(serverId: 'alpha'), isNull);
    expect(await vault.read(serverId: 'silo'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'unrelated'), 'keep');
  });
  test(
    'malformed scoped data fails closed without borrowing another account',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'sipflix_account_server_alpha': '{bad-json',
        'sipflix_account_username': 'legacy',
        'sipflix_account_password': 'legacy-password',
      });
      expect(await vault.read(serverId: 'alpha'), isNull);
    },
  );
}
