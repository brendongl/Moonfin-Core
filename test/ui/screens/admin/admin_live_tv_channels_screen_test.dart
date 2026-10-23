import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/emby/admin_live_tv_channels_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Emby's managed channels, in the shape a 4.10 server sends: numeric ids,
/// the tuner's management id and a 0-based sort index in display order.
class _FakeEmbyApi extends Fake implements EmbyAdminApi {
  _FakeEmbyApi(int count)
    : channels = [
        for (var i = 0; i < count; i++)
          {
            'Id': '${80854 + i}',
            'Name': i == 0 ? 'USA Disney Junior' : 'Channel ${i + 1}',
            'ManagementId': '533330de911a4c9b9fc21f1712a6f14b_hdhr_${i + 1}',
            'Disabled': false,
            'SortIndexNumber': i,
            'ChannelNumber': '${i + 1}',
          },
      ];

  final List<Map<String, dynamic>> channels;
  final calls = <String>[];

  @override
  Future<PremiereStatus> getPremiereStatus() async =>
      const PremiereStatus(isActive: false, hasKey: false);

  @override
  Future<Map<String, dynamic>> getManagedChannels({
    int startIndex = 0,
    int limit = 100,
  }) async {
    calls.add('get $startIndex $limit');
    return {
      'Items': [
        for (final c in channels.skip(startIndex).take(limit)) {...c},
      ],
      'TotalRecordCount': channels.length,
    };
  }

  @override
  Future<void> setChannelDisabled(
    String channelId, {
    required String managementId,
    required bool disabled,
  }) async {
    calls.add('disabled $channelId $managementId $disabled');
    channels.firstWhere((c) => c['Id'] == channelId)['Disabled'] = disabled;
  }

  @override
  Future<void> setChannelSortIndex(
    String channelId, {
    required String managementId,
    required int newIndex,
  }) async {
    calls.add('sort $channelId $managementId $newIndex');
    final channel = channels.firstWhere((c) => c['Id'] == channelId);
    channels
      ..remove(channel)
      ..insert(newIndex, channel);
  }
}

void main() {
  late _FakeEmbyApi emby;
  late AppLocalizations l10n;

  Future<void> pump(WidgetTester tester, int count) async {
    emby = _FakeEmbyApi(count);
    final client = _MockMediaServerClient();
    when(() => client.embyAdminApi).thenReturn(emby);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));

    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: AdminServerScope(
              serverType: ServerType.emby,
              child: AdminLiveTvChannelsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() async => GetIt.instance.reset());

  testWidgets('a channel turns off with its management id', (tester) async {
    await pump(tester, 2);
    expect(find.text('USA Disney Junior'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // Then reloads, since Emby renews the item id of a channel turned back on.
    expect(emby.calls.skip(1), [
      'disabled 80854 533330de911a4c9b9fc21f1712a6f14b_hdhr_1 true',
      'get 0 2',
    ]);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });

  testWidgets('a move posts the new index and reloads the order', (
    tester,
  ) async {
    await pump(tester, 3);

    await tester.tap(find.byTooltip(l10n.moveDown).first);
    await tester.pumpAndSettle();

    expect(emby.calls, [
      'get 0 100',
      'sort 80854 533330de911a4c9b9fc21f1712a6f14b_hdhr_1 1',
      'get 0 3',
    ]);
    final first = tester.getTopLeft(find.text('Channel 2'));
    final moved = tester.getTopLeft(find.text('USA Disney Junior'));
    expect(first.dy, lessThan(moved.dy));
    // The first can't go up.
    final up = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up).first,
    );
    expect(up.onPressed, isNull);
  });

  testWidgets('channels past the first page load on request', (tester) async {
    await pump(tester, 150);
    expect(emby.calls, ['get 0 100']);

    await tester.scrollUntilVisible(find.text(l10n.showMore), 600);
    await tester.tap(find.text(l10n.showMore));
    await tester.pumpAndSettle();

    expect(emby.calls.last, 'get 100 100');
    await tester.scrollUntilVisible(find.text('Channel 150'), 600);
    expect(find.text(l10n.showMore), findsNothing);
  });

  testWidgets('no channels says why, with a Premiere note', (tester) async {
    await pump(tester, 0);
    expect(find.text(l10n.adminLiveTvChannelsEmpty), findsOneWidget);
    expect(find.text(l10n.adminPremiereNoteLiveTv), findsOneWidget);
  });
}
