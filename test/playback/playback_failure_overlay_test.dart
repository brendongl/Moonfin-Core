import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/playback/playback_failure_overlay.dart';

void main() {
  testWidgets('checking state leaves Go back usable with a TV remote', (
    tester,
  ) async {
    var exits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackFailureOverlay(
            title: 'We’re checking this video',
            message: 'Checking our copy',
            checking: true,
            onBack: () => exits++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(exits, 1);
  });

  testWidgets(
    'confirmed missing file does not offer connection changes or retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackFailureOverlay(
              title: 'The video file is missing on our server',
              message: 'A replacement has been requested. Report #70.',
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('missing on our server'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Change connection'), findsNothing);
      expect(find.text('Go back'), findsOneWidget);
    },
  );

  testWidgets('error persists and both recovery actions work with a remote', (
    tester,
  ) async {
    var retries = 0;
    var exits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackFailureOverlay(
            message: 'The server could not convert this video (error 500).',
            onRetry: () => retries++,
            onBack: () => exits++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(find.textContaining('error 500'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(retries, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(exits, 1);
  });
  testWidgets('remote can select a different connection after failure', (
    tester,
  ) async {
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackFailureOverlay(
            message: 'Connection too slow',
            onRetry: () {},
            onBack: () {},
            onChangeConnection: () => changes++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(changes, 1);
  });
}
