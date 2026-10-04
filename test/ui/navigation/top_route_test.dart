import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/ui/navigation/top_route.dart';

void main() {
  GoRouter buildRouter() => GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      GoRoute(path: '/details/:id', builder: (_, _) => const Text('details')),
      GoRoute(path: '/player/video', builder: (_, _) => const Text('player')),
    ],
  );

  testWidgets('pushed player is on top even though uri still reads /home', (
    tester,
  ) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    unawaited(router.push('/details/1'));
    await tester.pumpAndSettle();
    unawaited(router.push('/player/video'));
    await tester.pumpAndSettle();

    final config = router.routerDelegate.currentConfiguration;
    expect(config.uri.path, '/home');
    expect(topRoutePath(config), '/player/video');
    expect(isPlayerPath(topRoutePath(config)), isTrue);
  });

  testWidgets('top page key changes when the player is popped', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    unawaited(router.push('/details/1'));
    await tester.pumpAndSettle();
    final detailsKey = topRoutePageKey(
      router.routerDelegate.currentConfiguration,
    );
    unawaited(router.push('/player/video'));
    await tester.pumpAndSettle();
    final playerKey = topRoutePageKey(
      router.routerDelegate.currentConfiguration,
    );
    expect(playerKey, isNot(detailsKey));

    router.pop();
    await tester.pumpAndSettle();
    final config = router.routerDelegate.currentConfiguration;
    expect(topRoutePageKey(config), detailsKey);
    expect(isPlayerPath(topRoutePath(config)), isFalse);
  });

  test('isPlayerPath', () {
    expect(isPlayerPath('/player/video'), isTrue);
    expect(isPlayerPath('/live-tv/player'), isTrue);
    expect(isPlayerPath('/game-player/x'), isTrue);
    expect(isPlayerPath('/home'), isFalse);
    expect(isPlayerPath('/details/1'), isFalse);
  });
}
