import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/settings/library_order_screen.dart';
import 'package:moonfin/ui/screens/settings/library_settings_screen.dart';
import 'package:server_core/server_core.dart';

class _Client extends Mock implements MediaServerClient {}

class _Users extends Mock implements UsersApi {}

class _Views extends Mock implements UserViewsApi {}

DioException failure() {
  final request = RequestOptions(
    path: 'https://emby2.n2.d-crypt.io/Users/secret-user/Views?api_key=SECRET',
  );
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: request,
      statusCode: 503,
      data: 'SECRET body',
    ),
  );
}

void main() {
  late _Users users;
  late _Views views;
  setUpAll(() => registerFallbackValue(const UserConfiguration()));
  setUp(() {
    users = _Users();
    views = _Views();
    final client = _Client();
    when(() => client.usersApi).thenReturn(users);
    when(() => client.userViewsApi).thenReturn(views);
    GetIt.I.registerSingleton<UserViewsRepository>(UserViewsRepository(client));
    when(() => users.getUserConfiguration())
        .thenAnswer((_) async => const UserConfiguration());
    when(() => views.getUserViews(includeHidden: true)).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'movies', 'Name': 'Movies', 'CollectionType': 'movies'},
        ],
      },
    );
    when(() => users.updateUserConfiguration(any())).thenAnswer((_) async {});
  });
  tearDown(() async => GetIt.I.reset());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectSafeDetails(WidgetTester tester, String operation) {
    final message = tester.widget<Text>(find.textContaining('HTTP 503')).data!;
    expect(message, contains(operation));
    expect(message, contains('Delta'));
    expect(message, contains('Direct'));
    expect(message, contains('Try again'));
    expect(message, isNot(contains('SECRET')));
    expect(message, isNot(contains('secret-user')));
    expect(message, isNot(contains('https://')));
  }

  for (final screen in <Widget>[
    const LibraryVisibilityScreen(),
    const LibraryOrderScreen(),
  ]) {
    testWidgets('${screen.runtimeType} gives safe route details and retries', (
      tester,
    ) async {
      when(() => views.getUserViews(includeHidden: true))
          .thenAnswer((_) async => throw failure());
      await pump(tester, screen);
      expectSafeDetails(tester, 'Load libraries');
      when(() => views.getUserViews(includeHidden: true)).thenAnswer(
        (_) async => {
          'Items': [
            {'Id': 'movies', 'Name': 'Movies', 'CollectionType': 'movies'},
          ],
        },
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 503'), findsNothing);
      expect(find.text('Movies'), findsOneWidget);
    });
  }

  testWidgets('visibility write failure rolls back and explains failure', (
    tester,
  ) async {
    when(() => users.updateUserConfiguration(any()))
        .thenAnswer((_) async => throw failure());
    await pump(tester, const LibraryVisibilityScreen());
    final tile = find.byType(SwitchListTile).first;
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    verify(() => users.updateUserConfiguration(any())).called(1);
    expectSafeDetails(tester, 'Save library visibility');
  });
}
