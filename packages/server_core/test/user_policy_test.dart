import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

void main() {
  test('a policy from the server goes back with every key', () {
    // Keys the typed fields never covered, which the server resets when left out.
    final json = <String, dynamic>{
      'IsAdministrator': false,
      'IsDisabled': false,
      'AccessSchedules': [
        {'DayOfWeek': 'Monday', 'StartHour': 8, 'EndHour': 20},
      ],
      'AllowedTags': ['kids'],
      'BlockUnratedItems': ['Movie'],
      'MaxParentalSubRating': 1,
      'SyncPlayAccess': 'JoinGroups',
      'EnableUserPreferenceAccess': false,
      'EnableContentDeletionFromFolders': ['f1'],
      'InvalidLoginAttemptCount': 2,
    };
    final policy = UserPolicy.fromJson(json);

    expect(policy.toJson(), json);
    expect(policy.toJson().containsKey('EnableSubtitleDownloading'), isFalse);
  });

  test('a policy built in code still serializes its fields', () {
    final json = const UserPolicy(isDisabled: true).toJson();
    expect(json['IsDisabled'], isTrue);
    expect(json['EnableAllFolders'], isTrue);
  });
}
