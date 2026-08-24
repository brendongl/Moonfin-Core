import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/playback/player_loading_overlay.dart';

// The loading screens are a support tool: a customer stuck on one reads it back
// verbatim. "Loading Stream..." covered three different phases and told nobody
// anything, so what the overlay renders is worth pinning down.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('finished steps render with a tick above the current label',
      (tester) async {
    await tester.pumpWidget(host(const PlayerLoadingOverlay(
      label: 'Opening stream...',
      steps: ['Closed previous stream', 'Connection tested'],
      detail: 'CDN 1  ·  Transcode',
    )));
    await tester.pump();

    expect(find.text('✓  Closed previous stream'), findsOneWidget);
    expect(find.text('✓  Connection tested'), findsOneWidget);
    // The label is upper-cased by the overlay.
    expect(find.text('OPENING STREAM...'), findsOneWidget);
    expect(find.text('CDN 1  ·  Transcode'), findsOneWidget);
  });

  testWidgets('no steps and no detail renders just the label', (tester) async {
    await tester.pumpWidget(
        host(const PlayerLoadingOverlay(label: 'Loading title details...')));
    await tester.pump();

    expect(find.textContaining('✓'), findsNothing);
    expect(find.text('LOADING TITLE DETAILS...'), findsOneWidget);
  });

  testWidgets('an empty detail string is not drawn as a blank line',
      (tester) async {
    await tester.pumpWidget(host(
        const PlayerLoadingOverlay(label: 'Buffering...', detail: '   ')));
    await tester.pump();

    expect(find.text('   '), findsNothing);
  });
}
