// Regression test for a Shield-reproduced dead end (swarm-20261004-batch2,
// findings R2-C issue 1 + R3-A): SipflixServers.injectOrMigrate used to skip
// re-injecting the hardcoded Sipflix server whenever `store.getServers()`
// was non-empty for ANY reason — including a box that also had an unrelated
// non-Sipflix server saved (e.g. a test device's "Jellyfin" entry). Combined
// with Sign Out All deleting every stored server (user_menu_dialog.dart
// `_signOutAll`), a box with a lingering Jellyfin record was left with zero
// Sipflix servers on every subsequent launch: `existing` stays null, but the
// old `isEmpty` guard never fires because Jellyfin keeps the list non-empty.
// Reproduced live on the gauntlet Shield: after Sign Out All plus its
// pre-existing Jellyfin entry, cold launch landed on the bare "Select
// Server" screen (Jellyfin only, "Discovered Servers: None found") forever.
import 'package:flutter_test/flutter_test.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthenticationStore authStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authStore = AuthenticationStore();
    await authStore.init();
  });

  test('a genuinely fresh install (no stored servers) injects the stub', () async {
    await SipflixServers.injectOrMigrate(authStore);
    final injected = authStore.getServer(SipflixServers.serverId);
    expect(injected, isNotNull);
    expect(injected!.name, SipflixServers.unsignedName);
  });

  test(
    'a box with only an unrelated non-Sipflix server (e.g. a test '
    'device\'s Jellyfin entry) still gets the Sipflix stub injected',
    () async {
      await authStore.putServer(
        Server(
          id: 'some-jellyfin-id',
          name: 'Jellyfin',
          address: 'http://192.168.50.101:8096',
          version: '10.11.11',
          serverType: ServerType.jellyfin,
          setupCompleted: true,
          dateAdded: DateTime(2026, 1, 1),
        ),
      );

      await SipflixServers.injectOrMigrate(authStore);

      final injected = authStore.getServer(SipflixServers.serverId);
      expect(injected, isNotNull, reason: 'Sipflix server must be injected '
          'even when a non-Sipflix server is already stored');
      expect(injected!.name, SipflixServers.unsignedName);
      // The unrelated server must be left alone.
      expect(authStore.getServer('some-jellyfin-id'), isNotNull);
    },
  );

  test(
    'a box already signed in to a different Sipflix server (Delta/iDuck, '
    'its own record id) does not get a duplicate AlphaV2 stub',
    () async {
      final deltaDef = SipflixServers.all.firstWhere((d) => d.key != 'AlphaV2');
      await authStore.putServer(deltaDef.toRecord());

      await SipflixServers.injectOrMigrate(authStore);

      // No AlphaV2 stub should have been created alongside the real one.
      expect(authStore.getServer(SipflixServers.serverId), isNull);
      expect(authStore.getServer(deltaDef.recordId), isNotNull);
    },
  );

  test(
    'reproduces the Shield dead end pre-fix and confirms the fix clears it: '
    'Sign Out All (deletes every server) on a box that also has Jellyfin',
    () async {
      // Arrange: box starts normally injected (AlphaV2 present) plus a
      // Jellyfin entry, matching the Shield's real state.
      await SipflixServers.injectOrMigrate(authStore);
      await authStore.putServer(
        Server(
          id: 'some-jellyfin-id',
          name: 'Jellyfin',
          address: 'http://192.168.50.101:8096',
          version: '10.11.11',
          serverType: ServerType.jellyfin,
          setupCompleted: true,
          dateAdded: DateTime(2026, 1, 1),
        ),
      );
      expect(authStore.getServer(SipflixServers.serverId), isNotNull);

      // Act: simulate `_signOutAll` deleting every stored server.
      for (final s in authStore.getServers()) {
        await authStore.removeServer(s.id);
      }
      expect(authStore.getServers(), isEmpty);

      // Re-add Jellyfin back (Sign Out All only ever touches servers that
      // existed at sign-out time; a real box's Jellyfin entry in this repro
      // is untouched by `_signOutAll` in practice, this just establishes
      // the "has a non-Sipflix server" precondition that triggered the bug).
      await authStore.putServer(
        Server(
          id: 'some-jellyfin-id',
          name: 'Jellyfin',
          address: 'http://192.168.50.101:8096',
          version: '10.11.11',
          serverType: ServerType.jellyfin,
          setupCompleted: true,
          dateAdded: DateTime(2026, 1, 1),
        ),
      );

      // Act: the fixed `_signOutCurrent`/`_signOutAll` route through
      // Destinations.startup, which re-runs injectOrMigrate on next launch.
      await SipflixServers.injectOrMigrate(authStore);

      // Assert: the Sipflix server must come back, not stay permanently gone.
      final injected = authStore.getServer(SipflixServers.serverId);
      expect(injected, isNotNull, reason: 'pre-fix this stayed null forever '
          'because Jellyfin kept getServers() non-empty');
    },
  );
}
