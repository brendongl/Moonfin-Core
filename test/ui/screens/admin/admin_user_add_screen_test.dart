import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/users/admin_user_add_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// The policy a fresh v12.2 user comes back with, trimmed to a few keys.
const _newPolicy = {
  'IsAdministrator': false,
  'EnableAllFolders': true,
  'EnabledFolders': <String>[],
  'EnableAllChannels': true,
  'EnabledChannels': <String>[],
  'SyncPlayAccess': 'CreateAndJoinGroups',
  'AccessSchedules': <Object>[],
};

class _FakeUsersApi extends Fake implements AdminUsersApi {
  List<Map<String, dynamic>> channels = const [];
  final created = <(String, String?)>[];
  final postedPolicies = <(String, Map<String, dynamic>)>[];
  bool failPolicy = false;

  @override
  Future<ServerUser> createUser(String name, String? password) async {
    created.add((name, password));
    return ServerUser.fromJson({
      'Id': 'new-id',
      'Name': name,
      'Policy': Map<String, dynamic>.from(_newPolicy),
    });
  }

  @override
  Future<void> updateUserPolicy(String userId, Map<String, dynamic> p) async {
    if (failPolicy) throw Exception('policy refused');
    postedPolicies.add((userId, p));
  }

  @override
  Future<List<Map<String, dynamic>>> getChannels({
    bool? supportsMediaDeletion,
  }) async =>
      channels;
}

class _FakeLibraryApi extends Fake implements AdminLibraryApi {
  @override
  Future<List<VirtualFolderInfo>> getMediaFolders({bool? isHidden}) async =>
      const [
        VirtualFolderInfo(name: 'Movies', itemId: 'movies-id'),
        VirtualFolderInfo(name: 'Shows', itemId: 'shows-id'),
      ];
}

void main() {
  late _FakeUsersApi users;
  late AppLocalizations l10n;

  setUp(() async {
    users = _FakeUsersApi();
    final client = _MockMediaServerClient();
    when(() => client.adminUsersApi).thenReturn(users);
    when(() => client.adminLibraryApi).thenReturn(_FakeLibraryApi());
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/admin/users/add',
      routes: [
        GoRoute(
          path: '/admin/users/add',
          builder: (_, _) => const Scaffold(body: AdminUserAddScreen()),
        ),
        GoRoute(
          path: '/admin/users/:userId',
          builder: (_, s) =>
              Scaffold(body: Text('edit ${s.pathParameters['userId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('create grants only the picked access and opens the user', (
    tester,
  ) async {
    users.channels = [
      {'Id': 'c1', 'Name': 'Podcasts'},
    ];
    await pump(tester);

    await tester.enterText(find.byType(TextFormField).first, ' kid ');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Movies'));
    await tester.pump();
    await tester.tap(find.text(l10n.create));
    await tester.pumpAndSettle();

    expect(users.created.single, ('kid', null));
    final (id, policy) = users.postedPolicies.single;
    expect(id, 'new-id');
    expect(policy, {
      ..._newPolicy,
      'EnableAllFolders': false,
      'EnabledFolders': ['movies-id'],
      'EnableAllChannels': false,
      'EnabledChannels': <String>[],
    });
    expect(find.text('edit new-id'), findsOneWidget);
  });

  // The user already exists by then, so a second create would only fail on
  // the taken name.
  testWidgets('a failed access save still opens the new user', (
    tester,
  ) async {
    users.failPolicy = true;
    await pump(tester);

    await tester.enterText(find.byType(TextFormField).first, 'kid');
    await tester.tap(find.text(l10n.create));
    await tester.pumpAndSettle();

    expect(users.created, hasLength(1));
    expect(find.text('edit new-id'), findsOneWidget);
    expect(
      find.textContaining(l10n.adminUserPolicyUpdateFailed('').trim()),
      findsOneWidget,
    );
  });

  testWidgets('channel access is hidden when the server has none', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.adminEnableAllLibraryAccess), findsOneWidget);
    expect(find.text(l10n.adminEnableAllChannels), findsNothing);
  });
}
