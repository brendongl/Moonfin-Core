import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_user_providers.dart';

Map<String, dynamic> _session(
  String device, {
  required DateTime lastActivity,
  String? userId = 'u1',
  bool playing = false,
}) => {
  'DeviceId': device,
  'LastActivityDate': lastActivity.toUtc().toIso8601String(),
  'UserId': ?userId,
  if (playing) 'NowPlayingItem': {'Id': 'item'},
};

void main() {
  final now = DateTime.utc(2026, 10, 16, 12);

  test('a push updates the matching device and adds new ones', () {
    final current = [
      _session('tv', lastActivity: now.subtract(const Duration(minutes: 10))),
    ];
    final merged = mergeLiveSessions(current, [
      _session('tv', lastActivity: now, playing: true),
      _session('phone', lastActivity: now),
    ], now);

    expect(merged.map((s) => s['DeviceId']), ['tv', 'phone']);
    expect(merged.first['NowPlayingItem'], isNotNull);
  });

  // A pushed entry older than 95 s, or neither playing nor tied to a user, is
  // ignored.
  test('stale and anonymous pushed sessions are left out', () {
    final merged = mergeLiveSessions(const [], [
      _session('old', lastActivity: now.subtract(const Duration(seconds: 96))),
      _session('anon', lastActivity: now, userId: null),
      _session('fresh', lastActivity: now.subtract(const Duration(seconds: 95))),
    ], now);

    expect(merged.map((s) => s['DeviceId']), ['fresh']);
  });

  test('a session missing from a push is kept', () {
    final current = [_session('tv', lastActivity: now)];
    final merged = mergeLiveSessions(current, [
      _session('phone', lastActivity: now),
    ], now);

    expect(merged.map((s) => s['DeviceId']), ['tv', 'phone']);
  });

  test('a null clock lays already filtered pushes over a fresh load', () {
    final loaded = [
      _session('tv', lastActivity: now.subtract(const Duration(minutes: 5))),
    ];
    final merged = mergeLiveSessions(loaded, [
      _session('tv', lastActivity: now, playing: true),
    ], null);

    expect(merged, hasLength(1));
    expect(merged.single['NowPlayingItem'], isNotNull);
  });
}
