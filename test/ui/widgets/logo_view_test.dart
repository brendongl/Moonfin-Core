import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/logo_view.dart';

/// Never finishes loading, like a logo stuck behind a wedged connection.
class _HangingImage extends ImageProvider<_HangingImage> {
  const _HangingImage();

  @override
  Future<_HangingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_HangingImage key, ImageDecoderCallback _) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// Fails at once, like a 404 for the logo.
class _FailingImage extends ImageProvider<_FailingImage> {
  const _FailingImage();

  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_FailingImage key, ImageDecoderCallback _) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.error(StateError('404')));
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('a failed logo shows the title instead', (tester) async {
    await tester.pumpWidget(
      _host(
        const LogoView(imageProvider: _FailingImage(), fallback: Text('M3GAN')),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('M3GAN'), findsOneWidget);
  });

  testWidgets('a slow logo shows the title after the delay', (tester) async {
    await tester.pumpWidget(
      _host(
        const LogoView(
          imageProvider: _HangingImage(),
          fallback: Text('Cosmic Princess Kaguya!'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cosmic Princess Kaguya!'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Cosmic Princess Kaguya!'), findsOneWidget);
  });

  testWidgets('no fallback keeps the old empty behaviour', (tester) async {
    await tester.pumpWidget(
      _host(const LogoView(imageProvider: _FailingImage())),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Text), findsNothing);
  });
}
