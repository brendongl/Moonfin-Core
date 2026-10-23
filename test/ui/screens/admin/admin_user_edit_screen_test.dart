import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/users/admin_user_edit_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

const _userId = 'fa030fcaad884e85b9eaad296e00c7cc';

/// A 12.2 server's UserDto.
Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/admin/user.json').readAsStringSync())
        as Map<String, dynamic>;

/// An Emby 4.9 server's UserDto, which leaves out what Emby doesn't have.
Map<String, dynamic> _embyUser() => {
      'Name': 'second',
      'ServerId': '2c58c82b8fa14a4899e23627cb1bea10',
      'Id': _userId,
      'HasPassword': false,
      'Configuration': {'SubtitleMode': 'Smart', 'OrderedViews': []},
      'Policy': {
        'IsAdministrator': false,
        'IsHidden': false,
        'IsHiddenRemotely': true,
        'IsHiddenFromUnusedDevices': false,
        'IsDisabled': false,
        'LockedOutDate': 0,
        'AllowTagOrRating': false,
        'BlockedTags': [],
        'IsTagBlockingModeInclusive': false,
        'IncludeTags': [],
        'EnableUserPreferenceAccess': true,
        'AccessSchedules': [],
        'BlockUnratedItems': [],
        'EnableRemoteControlOfOtherUsers': false,
        'EnableSharedDeviceControl': true,
        'EnableRemoteAccess': true,
        'EnableLiveTvManagement': true,
        'EnableLiveTvAccess': true,
        'EnableMediaPlayback': true,
        'EnableAudioPlaybackTranscoding': true,
        'EnableVideoPlaybackTranscoding': true,
        'AutoRemoteQuality': 0,
        'EnablePlaybackRemuxing': true,
        'EnableContentDeletion': false,
        'RestrictedFeatures': [],
        'EnableContentDeletionFromFolders': [],
        'EnableContentDownloading': true,
        'EnableSubtitleDownloading': true,
        'EnableSubtitleManagement': false,
        'EnableSyncTranscoding': true,
        'EnableMediaConversion': true,
        'EnabledChannels': [],
        'EnableAllChannels': true,
        'EnabledFolders': [],
        'EnableAllFolders': true,
        'InvalidLoginAttemptCount': 0,
        'EnablePublicSharing': true,
        'RemoteClientBitrateLimit': 0,
        'AuthenticationProviderId':
            'Emby.Server.Implementations.Library.DefaultAuthenticationProvider',
        'ExcludedSubFolders': [],
        'SimultaneousStreamLimit': 0,
        'EnabledDevices': [],
        'EnableAllDevices': true,
        'AllowCameraUpload': true,
        'AllowSharingPersonalItems': false,
      },
    };

Map<String, dynamic> _copy(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

class _FakeUsersApi extends Fake implements AdminUsersApi {
  Map<String, dynamic> user = _fixture();
  List<Map<String, dynamic>> channels = const [];
  List<Map<String, dynamic>> deletableChannels = const [];
  final postedUsers = <Map<String, dynamic>>[];
  final postedPolicies = <Map<String, dynamic>>[];
  final passwords = <Map<String, Object?>>[];

  Map<String, dynamic> get policy => user['Policy'] as Map<String, dynamic>;

  @override
  Future<ServerUser> getUserById(String userId) async =>
      ServerUser.fromJson(_copy(user));

  @override
  Future<void> updateUser(String userId, Map<String, dynamic> body) async {
    expect(userId, _userId);
    postedUsers.add(_copy(body));
  }

  @override
  Future<void> updateUserPolicy(String userId, Map<String, dynamic> p) async {
    expect(userId, _userId);
    postedPolicies.add(_copy(p));
    user = {...user, 'Policy': _copy(p)};
  }

  @override
  Future<void> updateUserPassword(
    String userId, {
    String? currentPassword,
    String? newPassword,
    bool resetPassword = false,
  }) async {
    passwords.add({
      'current': currentPassword,
      'new': newPassword,
      'reset': resetPassword,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getChannels({
    bool? supportsMediaDeletion,
  }) async =>
      supportsMediaDeletion == true ? deletableChannels : channels;
}

class _FakeLibraryApi extends Fake implements AdminLibraryApi {
  @override
  Future<List<VirtualFolderInfo>> getMediaFolders({bool? isHidden}) async =>
      const [
        VirtualFolderInfo(name: 'Movies', itemId: 'movies-id'),
        VirtualFolderInfo(name: 'Shows', itemId: 'shows-id'),
      ];
}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  List<Map<String, dynamic>> ratings = const [];
  bool remoteAccess = true;

  @override
  Future<List<Map<String, dynamic>>> getParentalRatings() async => ratings;

  @override
  Future<List<Map<String, dynamic>>> getAuthProviders() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getPasswordResetProviders() async =>
      const [];

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async =>
      {'EnableRemoteAccess': remoteAccess};

  /// Where Emby keeps the remote access switch.
  @override
  Future<Map<String, dynamic>> getServerConfiguration() async =>
      {'EnableRemoteAccess': remoteAccess};
}

class _FakeEmbyApi extends Fake implements EmbyAdminApi {
  _FakeEmbyApi(this.users);

  final _FakeUsersApi users;
  final links = <String>[];
  int unlinks = 0;
  Object? linkError;

  @override
  Future<PremiereStatus> getPremiereStatus() async =>
      const PremiereStatus(isActive: false, hasKey: false);

  @override
  Future<Map<String, dynamic>> linkConnectUser(
    String userId,
    String connectUsername,
  ) async {
    expect(userId, _userId);
    if (linkError != null) throw linkError!;
    links.add(connectUsername);
    users.user['ConnectUserName'] = connectUsername;
    return {'IsPending': false, 'IsNewUserInvitation': false};
  }

  @override
  Future<void> unlinkConnectUser(String userId) async {
    expect(userId, _userId);
    unlinks++;
    users.user.remove('ConnectUserName');
  }
}

class _FakeDevicesApi extends Fake implements AdminDevicesApi {
  @override
  Future<List<DeviceInfoDto>> getDevices({String? userId}) async => const [];
}

void main() {
  late _FakeUsersApi users;
  late _FakeSystemApi system;
  late _FakeEmbyApi emby;
  late _MockMediaServerClient client;
  late AppLocalizations l10n;

  setUp(() async {
    users = _FakeUsersApi();
    system = _FakeSystemApi();
    client = _MockMediaServerClient();
    when(() => client.adminUsersApi).thenReturn(users);
    when(() => client.adminLibraryApi).thenReturn(_FakeLibraryApi());
    when(() => client.adminSystemApi).thenReturn(system);
    when(() => client.adminDevicesApi).thenReturn(_FakeDevicesApi());
    emby = _FakeEmbyApi(users);
    when(() => client.embyAdminApi).thenReturn(emby);
    when(() => client.userId).thenReturn('someone-else');
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester, {bool onEmby = false}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const page = AdminUserEditScreen(userId: _userId);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: onEmby
                ? const AdminServerScope(
                    serverType: ServerType.emby,
                    child: page,
                  )
                : page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Padding))
            .first,
        matching: find.byType(TextField),
      );

  Future<void> toggle(WidgetTester tester, String title) async {
    await tester.tap(find.widgetWithText(SwitchListTile, title));
    await tester.pump();
  }

  // The first row with [title]: Movies is a library and a deletion row.
  Future<void> check(WidgetTester tester, String title) async {
    await tester.tap(find.widgetWithText(CheckboxListTile, title).first);
    await tester.pump();
  }

  Future<void> pick(WidgetTester tester, Finder dropdown, String item) async {
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  Future<void> save() async {
    expect(await AdminDraft.active.value!.save(), isTrue);
  }

  testWidgets('a policy save keeps every key it never showed', (tester) async {
    // Schedules are hidden for administrators, so this page never shows them.
    users.user['Policy'] = {
      ...users.policy,
      'IsAdministrator': true,
      'AccessSchedules': [
        {'DayOfWeek': 'Monday', 'StartHour': 8, 'EndHour': 20},
      ],
      'AllowedTags': ['kids'],
      'BlockUnratedItems': ['Movie'],
      'MaxParentalRating': 10,
      'MaxParentalSubRating': 1,
      'SyncPlayAccess': 'JoinGroups',
      'EnableUserPreferenceAccess': false,
      'EnableContentDeletionFromFolders': ['movies-id'],
      'InvalidLoginAttemptCount': 2,
    };
    final before = _copy(users.policy);
    await pump(tester);
    await openTab(tester, l10n.access);
    expect(find.text(l10n.adminDeviceAccess.toUpperCase()), findsNothing);
    await openTab(tester, l10n.adminParentalControl);
    expect(find.text(l10n.adminAccessSchedules.toUpperCase()), findsNothing);
    await openTab(tester, l10n.permissions);

    await toggle(tester, l10n.adminHiddenUser);
    await save();

    expect(users.postedUsers, isEmpty);
    expect(users.postedPolicies.single, {...before, 'IsHidden': false});
  });

  testWidgets('rename posts the whole UserDto with its Configuration', (
    tester,
  ) async {
    final config = _copy(users.user['Configuration'] as Map<String, dynamic>);
    await pump(tester);

    await tester.enterText(field(l10n.username), '  kid ');
    await tester.pump();
    await save();

    final posted = users.postedUsers.single;
    expect(posted['Name'], 'kid');
    expect(posted['Configuration'], config);
    expect(posted['ServerId'], users.user['ServerId']);
    expect(users.postedPolicies, isEmpty);
  });

  testWidgets('each control type posts its value', (tester) async {
    final keys = users.policy.keys.toSet();
    await pump(tester);
    await openTab(tester, l10n.permissions);

    await toggle(tester, l10n.adminAllowLiveTvAccess);
    await tester.enterText(field(l10n.adminRemoteBitrateLimitMbps), '8.5');
    await tester.enterText(field(l10n.adminMaxActiveSessions), '');
    await tester.enterText(field(l10n.adminLoginAttemptsBeforeLockout), '');
    await tester.pump();
    await pick(
      tester,
      find.byType(DropdownButtonFormField<String>).last,
      l10n.adminSyncPlayNone,
    );

    await openTab(tester, l10n.access);
    await toggle(tester, l10n.adminEnableAllLibraryAccess);
    await check(tester, 'Movies');

    await openTab(tester, l10n.adminParentalControl);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.adminAddTag).first,
      'kids',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await check(tester, l10n.adminUnratedMovie);

    await save();
    final p = users.postedPolicies.single;
    expect(p['EnableLiveTvAccess'], isFalse);
    expect(p['RemoteClientBitrateLimit'], 8500000);
    // The server's ints aren't nullable, so empty fields post 0.
    expect(p['MaxActiveSessions'], 0);
    expect(p['LoginAttemptsBeforeLockout'], 0);
    expect(p['SyncPlayAccess'], 'None');
    expect(p['EnableAllFolders'], isFalse);
    expect(p['EnabledFolders'], ['movies-id']);
    expect(p['AllowedTags'], ['kids']);
    expect(p['BlockUnratedItems'], ['Movie']);
    expect(p.keys.toSet(), keys);
  });

  testWidgets('the bitrate limit shows in Mbps', (tester) async {
    users.policy['RemoteClientBitrateLimit'] = 12000000;
    await pump(tester);
    await openTab(tester, l10n.permissions);
    expect(
      find.descendant(
        of: field(l10n.adminRemoteBitrateLimitMbps),
        matching: find.text('12'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ratings that share a score keep their own sub score', (
    tester,
  ) async {
    system.ratings = [
      {'Name': 'Unrated'},
      {'Name': 'G', 'Value': 0, 'RatingScore': {'score': 0, 'subScore': 0}},
      {'Name': 'TV-G', 'Value': 0, 'RatingScore': {'score': 0, 'subScore': 0}},
      {'Name': 'TV-Y7', 'Value': 7, 'RatingScore': {'score': 7, 'subScore': 0}},
      {
        'Name': 'TV-Y7-FV',
        'Value': 7,
        'RatingScore': {'score': 7, 'subScore': 1},
      },
    ];
    await pump(tester);
    await openTab(tester, l10n.adminParentalControl);

    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    // Neighbours with one score and sub score share an option.
    expect(find.text('G/TV-G'), findsWidgets);
    await tester.tap(find.text('TV-Y7-FV').last);
    await tester.pumpAndSettle();

    await save();
    expect(users.postedPolicies.single['MaxParentalRating'], 7);
    expect(users.postedPolicies.single['MaxParentalSubRating'], 1);
  });

  testWidgets('access lists channels and saves the picked ones', (
    tester,
  ) async {
    users.channels = [
      {'Id': 'c1', 'Name': 'Podcasts'},
    ];
    await pump(tester);
    await openTab(tester, l10n.access);

    await toggle(tester, l10n.adminEnableAllChannels);
    await check(tester, 'Podcasts');
    await save();

    expect(users.postedPolicies.single['EnableAllChannels'], isFalse);
    expect(users.postedPolicies.single['EnabledChannels'], ['c1']);
  });

  testWidgets('channel access is hidden when the server has none', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, l10n.access);
    expect(find.text(l10n.adminEnableAllChannels), findsNothing);
  });

  testWidgets('deletion lists deletable channels and all clears the list', (
    tester,
  ) async {
    users.deletableChannels = [
      {'Id': 'c1', 'Name': 'Podcasts'},
    ];
    users.policy['EnableContentDeletionFromFolders'] = ['c1'];
    await pump(tester);
    await openTab(tester, l10n.access);

    final row = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Podcasts'),
    );
    expect(row.value, isTrue);

    await toggle(tester, l10n.adminDeleteFromAllLibraries);
    await save();
    expect(users.postedPolicies.single['EnableContentDeletion'], isTrue);
    expect(users.postedPolicies.single['EnableContentDeletionFromFolders'],
        isEmpty);
  });

  testWidgets('parental control shows what the server has', (tester) async {
    users.user['Policy'] = {
      ...users.policy,
      'AllowedTags': ['kids'],
      'BlockUnratedItems': ['Movie'],
      'AccessSchedules': [
        {'DayOfWeek': 'Monday', 'StartHour': 8.5, 'EndHour': 20},
      ],
    };
    await pump(tester);
    await openTab(tester, l10n.adminParentalControl);

    expect(find.widgetWithText(Chip, 'kids'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, l10n.adminUnratedMovie),
          )
          .value,
      isTrue,
    );
    expect(find.text(l10n.adminDayMonday), findsOneWidget);
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
  });

  testWidgets('a schedule that ends before it starts is refused', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, l10n.adminParentalControl);
    await tester.tap(find.text(l10n.adminAddSchedule));
    await tester.pumpAndSettle();

    final end = find.byType(DropdownButtonFormField<double>).last;
    await tester.scrollUntilVisible(end, 100,
        scrollable: find.byType(Scrollable).last);
    await pick(tester, end, '00:00');
    expect(find.text(l10n.adminScheduleStartBeforeEnd), findsOneWidget);

    expect(await AdminDraft.active.value!.save(), isFalse);
    expect(users.postedPolicies, isEmpty);
  });

  testWidgets('remote access is hidden while the server turns it off', (
    tester,
  ) async {
    system.remoteAccess = false;
    await pump(tester);
    await openTab(tester, l10n.permissions);
    expect(find.text(l10n.adminAllowRemoteAccess), findsNothing);
  });

  testWidgets('an admin changing their own password sends the current one', (
    tester,
  ) async {
    when(() => client.userId).thenReturn(_userId);
    users.policy['IsAdministrator'] = true;
    await pump(tester);
    await openTab(tester, l10n.password);

    // No reset for administrators.
    expect(find.text(l10n.adminResetPassword), findsNothing);
    await tester.enterText(field(l10n.adminCurrentPassword), 'old');
    await tester.enterText(field(l10n.adminNewPassword), 'new');
    await tester.enterText(field(l10n.adminConfirmPassword), 'new');
    await tester.tap(find.text(l10n.adminSetPassword));
    await tester.pumpAndSettle();

    expect(users.passwords.single,
        {'current': 'old', 'new': 'new', 'reset': false});
  });

  testWidgets('an empty password is refused for an administrator', (
    tester,
  ) async {
    users.policy['IsAdministrator'] = true;
    await pump(tester);
    await openTab(tester, l10n.password);
    expect(find.text(l10n.adminCurrentPassword), findsNothing);

    await tester.tap(find.text(l10n.adminSetPassword));
    await tester.pumpAndSettle();
    expect(users.passwords, isEmpty);
    expect(find.text(l10n.adminNewPasswordEmpty), findsOneWidget);
  });

  testWidgets('an empty password for a user is set, not reset', (tester) async {
    await pump(tester);
    await openTab(tester, l10n.password);
    await tester.tap(find.text(l10n.adminSetPassword));
    await tester.pumpAndSettle();
    expect(users.passwords.single, {'current': null, 'new': '', 'reset': false});
  });

  testWidgets('reset asks first and then resets', (tester) async {
    await pump(tester);
    await openTab(tester, l10n.password);
    await tester.tap(find.text(l10n.adminResetPassword));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.reset));
    await tester.pumpAndSettle();
    expect(users.passwords.single, {'current': null, 'new': null, 'reset': true});
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    for (final tab in [
      l10n.profile,
      l10n.permissions,
      l10n.access,
      l10n.adminParentalControl,
    ]) {
      await openTab(tester, tab);
      expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
    }
  });

  group('on Emby', () {
    setUp(() => users.user = _embyUser());

    testWidgets('Jellyfin rows hide and Emby rows save', (tester) async {
      final keys = users.policy.keys.toSet();
      await pump(tester, onEmby: true);
      await openTab(tester, l10n.permissions);

      for (final label in [
        l10n.adminForceRemoteTranscoding,
        l10n.adminMaxActiveSessions,
        l10n.adminAllowCollectionManagement,
        l10n.adminAllowLyricManagement,
        l10n.adminLoginAttemptsBeforeLockout,
        l10n.adminSyncPlayAccess,
        l10n.authentication.toUpperCase(),
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text(l10n.adminPremiereNote), findsOneWidget);

      await toggle(tester, l10n.adminHiddenRemotely);
      await toggle(tester, l10n.adminAllowCameraUpload);
      await toggle(tester, l10n.adminAllowSharingPersonalItems);
      await toggle(tester, l10n.adminAllowSubtitleDownloading);
      await tester.enterText(field(l10n.adminAutoRemoteQuality), '4');
      await tester.pump();
      await pick(tester, find.byType(DropdownButtonFormField<int>), '3');

      await openTab(tester, l10n.adminParentalControl);
      expect(find.text(l10n.adminAllowedTagsHint), findsNothing);
      await pick(
        tester,
        find.byType(DropdownButtonFormField<bool>),
        l10n.adminAllowedTags,
      );
      expect(find.text(l10n.adminAllowedTagsHint), findsOneWidget);

      await save();
      final p = users.postedPolicies.single;
      expect(p['IsHiddenRemotely'], isFalse);
      expect(p['AllowCameraUpload'], isFalse);
      expect(p['AllowSharingPersonalItems'], isTrue);
      expect(p['EnableSubtitleDownloading'], isFalse);
      expect(p['AutoRemoteQuality'], 4000000);
      expect(p['SimultaneousStreamLimit'], 3);
      expect(p['IsTagBlockingModeInclusive'], isTrue);
      // Nothing Jellyfin only is added.
      expect(p.keys.toSet(), keys);
    });

    testWidgets('Emby Connect links and unlinks at once', (tester) async {
      await pump(tester, onEmby: true);
      final connect = field(l10n.adminEmbyConnectUser);

      await tester.enterText(connect, 'someone@example.com');
      await tester.pump();
      await tester.tap(find.text(l10n.adminEmbyConnectLink));
      await tester.pumpAndSettle();
      expect(emby.links, ['someone@example.com']);
      expect(find.text(l10n.adminEmbyConnectUnlink), findsOneWidget);

      await tester.tap(find.text(l10n.adminEmbyConnectUnlink));
      await tester.pumpAndSettle();
      expect(emby.unlinks, 1);
      expect(find.text(l10n.adminEmbyConnectLink), findsOneWidget);
      // Neither touches the draft.
      expect(AdminDraft.active.value!.isDirty, isFalse);
    });

    testWidgets('an unknown Emby Connect account says so', (tester) async {
      final request = RequestOptions(path: '/Users/$_userId/Connect/Link');
      emby.linkError = DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 500,
          data: 'NotFound',
        ),
      );
      await pump(tester, onEmby: true);
      await tester.enterText(field(l10n.adminEmbyConnectUser), 'nobody');
      await tester.pump();
      await tester.tap(find.text(l10n.adminEmbyConnectLink));
      await tester.pumpAndSettle();
      expect(find.text(l10n.adminEmbyConnectNotFound), findsOneWidget);
    });

    testWidgets('Jellyfin has no Emby rows', (tester) async {
      users.user = _fixture();
      await pump(tester);
      expect(find.text(l10n.adminEmbyConnect.toUpperCase()), findsNothing);
      await openTab(tester, l10n.permissions);
      expect(find.text(l10n.adminAllowMediaConversion), findsNothing);
      expect(find.text(l10n.adminStreamingStreamLimit), findsNothing);
    });
  });
}
