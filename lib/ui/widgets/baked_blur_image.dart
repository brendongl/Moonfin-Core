import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Paints [image] blurred, drawing the blur once when the source loads.
///
/// An ImageFiltered blur runs on the GPU every time its layer is drawn, so a
/// full-screen backdrop under a crossfade or a scrolling row pays for it on
/// every frame. Baked, the backdrop is a plain image, and a fade over it can
/// apply its opacity straight to the image draw.
class BakedBlurImage extends StatefulWidget {
  const BakedBlurImage({
    super.key,
    required this.image,
    required this.sigma,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final ImageProvider image;

  /// In logical pixels of the painted box, the unit an ImageFiltered around
  /// the image would use.
  final double sigma;

  final BoxFit fit;
  final Alignment alignment;

  @override
  State<BakedBlurImage> createState() => _BakedBlurImageState();
}

class _BakedBlurImageState extends State<BakedBlurImage> {
  // A failed load paints nothing.
  late final _listener = ImageStreamListener(_onImage, onError: (_, _) {});
  ImageStream? _stream;
  ImageInfo? _source;
  ui.Image? _baked;
  Size? _bakedSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BakedBlurImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _resolve();
    if (widget.sigma != oldWidget.sigma || widget.fit != oldWidget.fit) {
      _bakedSize = null;
    }
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    setState(() {
      _source?.dispose();
      _source = info;
      _bakedSize = null;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _source?.dispose();
    _baked?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final source = _source;
        if (source != null &&
            size != _bakedSize &&
            size.isFinite &&
            !size.isEmpty) {
          _baked?.dispose();
          _baked = _bake(source.image, size);
          _bakedSize = size;
        }
        return RawImage(
          image: _baked,
          fit: widget.fit,
          alignment: widget.alignment,
        );
      },
    );
  }

  ui.Image _bake(ui.Image source, Size box) {
    final fitted = applyBoxFit(
      widget.fit,
      Size(source.width.toDouble(), source.height.toDouble()),
      box,
    );
    // The blur runs on the decoded pixels, which are scaled up or down to
    // the box, so the sigma follows that scale.
    final sigma = widget.sigma * fitted.source.width / fitted.destination.width;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(
      source,
      Offset.zero,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
    );
    final picture = recorder.endRecording();
    final baked = picture.toImageSync(source.width, source.height);
    picture.dispose();
    return baked;
  }
}
