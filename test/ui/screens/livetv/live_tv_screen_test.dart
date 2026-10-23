import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/livetv/live_tv_screen.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';
import 'package:moonfin/util/platform_detection.dart';

import '../../widgets/bottom_nav/bottom_nav_fakes.dart';

Future<GoRouter> _open(WidgetTester tester, InterfaceLayout layout) async {
  final setup = await setUpBottomNav();
  PlatformDetection.setInterfaceLayout(layout);
  await setup.prefs.set(UserPreferences.navbarPosition, NavbarPosition.top);
  NavigationLayout.positionNotifier.value = NavbarPosition.top;
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: Destinations.home,
    routes: [
      GoRoute(
        path: Destinations.home,
        builder: (_, _) => const Scaffold(body: Text('home page')),
      ),
      GoRoute(
        path: Destinations.liveTv,
        builder: (_, _) => const LiveTvScreen(),
        routes: [
          GoRoute(
            path: 'guide',
            builder: (_, _) => const Scaffold(body: Text('guide page')),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
  return router;
}

void main() {
  tearDown(tearDownBottomNav);

  testWidgets('backing out of the guide on the web still leaves a way home', (
    tester,
  ) async {
    final router = await _open(tester, InterfaceLayout.desktop);
    // The web navbar goes to the guide, which puts the landing page under it.
    router.go(Destinations.liveTvGuide);
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(LiveTvScreen), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Live TV')).dy,
      greaterThanOrEqualTo(
        TopToolbar.heightFor(tester.element(find.byType(LiveTvScreen))),
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('TV keeps the page without the navbar', (tester) async {
    final router = await _open(tester, InterfaceLayout.tv);
    router.go(Destinations.liveTv);
    await tester.pumpAndSettle();

    expect(find.byType(LiveTvScreen), findsOneWidget);
    expect(find.byType(NavigationLayout), findsNothing);
  });
}
