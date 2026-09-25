// Operator-only UI harness. Not imported by lib/main.dart and never shipped
// as the customer application. All report responses below are fixtures.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin/sipflix/sipflix_playback_report.dart';
import 'package:moonfin/ui/widgets/playback/playback_failure_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
  ]);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const _Preview(),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  String? scenario;
  late final controller =
      SipflixPlaybackReportController(
        endpoint: 'https://preview.invalid/v1/playback-failures',
        post: (_, token, cancel) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return switch (scenario) {
            'Missing file / report accepted' => {
              'diagnosis': 'missing',
              'reportStatus': 'replacement_requested',
              'issueId': 70,
            },
            'Missing file / report failed' => {
              'diagnosis': 'missing',
              'reportStatus': 'auth_required',
            },
            _ => {'diagnosis': 'source_readable', 'reportStatus': 'not_sent'},
          };
        },
      )..addListener(() {
        if (mounted) setState(() {});
      });

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void open(String value) {
    setState(() {
      scenario = value;
    });
    unawaited(
      controller.check(
        failureKey: value,
        token: 'test-fixture-not-a-token',
        userId: 'test',
        itemId: '6',
        mediaSourceId: 'fixture',
        playMethod: 'transcode',
        httpStatus: 500,
        appVersion: 'preview',
      ),
    );
  }

  void back() {
    setState(() {
      controller.reset();
      scenario = null;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: scenario == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: Scaffold(
      body: Stack(
        children: [
          if (scenario == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Playback reporting — device acceptance',
                    style: TextStyle(fontSize: 26),
                  ),
                  const SizedBox(height: 24),
                  for (final name in [
                    'Missing file / report accepted',
                    'Missing file / report failed',
                    'Source readable',
                  ])
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: FilledButton(
                        autofocus: name == 'Missing file / report accepted',
                        onPressed: () => open(name),
                        child: Text(name),
                      ),
                    ),
                ],
              ),
            ),
          if (scenario != null)
            PlaybackFailureOverlay(
              title: controller.checking
                  ? 'We’re checking this video'
                  : controller.result?.title ?? '',
              message: controller.checking
                  ? 'Playback failed. We’re checking our copy and whether it needs to be reported.'
                  : controller.result?.message ?? '',
              checking: controller.checking,
              onBack: back,
              onRetry:
                  !controller.checking && controller.result?.isMissing != true
                  ? back
                  : null,
            ),
          const Positioned(
            top: 16,
            left: 24,
            child: Text(
              'TEST PREVIEW • FIXTURE DATA • NO REPORT SENT',
              style: TextStyle(color: Colors.amber, fontSize: 16),
            ),
          ),
        ],
      ),
    ),
  );
}
