import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/libraries/admin_library_nfo_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> nfo = {
    'UserId': 'u1',
    'ReleaseDateFormat': '',
    'SaveImagePathsInNfo': true,
    'EnablePathSubstitution': true,
    'EnableExtraThumbsDuplication': false,
  };
  final posted = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async =>
      Map<String, dynamic>.from(nfo);

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    posted.add((key, config));
    nfo = Map<String, dynamic>.from(config);
  }
}

class _FakeUsersApi extends Fake implements AdminUsersApi {
  bool fail = false;

  @override
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden}) async {
    if (fail) throw Exception('users down');
    return const [ServerUser(id: 'u1', name: 'Axl')];
  }
}

void main() {
  late _FakeSystemApi api;
  late _FakeUsersApi users;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    users = _FakeUsersApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    when(() => client.adminUsersApi).thenReturn(users);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminLibraryNfoScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a switch and the user pick post the xbmcmetadata config', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(l10n.adminLibExtraThumbs));
    await tester.pump();
    await tester.tap(find.text('Axl'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminLibNone).last);
    await tester.pumpAndSettle();

    expect(await AdminDraft.active.value!.save(), isTrue);

    final (key, body) = api.posted.single;
    expect(key, 'xbmcmetadata');
    // '' for no user, and a default release date format.
    expect(body, {
      'UserId': '',
      'ReleaseDateFormat': 'yyyy-MM-dd',
      'SaveImagePathsInNfo': true,
      'EnablePathSubstitution': true,
      'EnableExtraThumbsDuplication': true,
    });
  });

  testWidgets('a failed user list shows the error', (tester) async {
    users.fail = true;
    await pump(tester);

    expect(find.text(l10n.adminSettingsLoadFailed), findsOneWidget);
    expect(AdminDraft.active.value, isNull);
  });
}
