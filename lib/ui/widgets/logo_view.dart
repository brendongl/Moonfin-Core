import 'dart:async';
import 'dart:ui' as ui;

import 'offline_aware_image.dart';

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// A logo display widget with a drop shadow that follows the image shape.
///
/// Sipflix fork: with a [fallback], that widget (normally the title as text)
/// stands in when the logo fails to load, and while it is still loading past
/// [fallbackDelay], so a slow or missing logo never leaves the title blank.
class LogoView extends StatefulWidget {
  final String? imageUrl;
  final ImageProvider? imageProvider;
  final double maxHeight;
  final double maxWidth;
  final Widget? fallback;
  final Duration fallbackDelay;

  const LogoView({
    super.key,
    this.imageUrl,
    this.imageProvider,
    this.maxHeight = 80,
    this.maxWidth = 200,
    this.fallback,
    this.fallbackDelay = const Duration(milliseconds: 600),
  });

  @override
  State<LogoView> createState() => _LogoViewState();
}

class _LogoViewState extends State<LogoView> {
  Timer? _slow;
  bool _showFallbackWhileLoading = false;

  ImageProvider? get _effectiveProvider {
    if (widget.imageProvider != null) return widget.imageProvider;
    final url = widget.imageUrl;
    if (url != null && url.isNotEmpty) return offlineAwareImageProvider(url);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _armFallback();
  }

  @override
  void didUpdateWidget(LogoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.imageProvider != widget.imageProvider) {
      _showFallbackWhileLoading = false;
      _armFallback();
    }
  }

  void _armFallback() {
    _slow?.cancel();
    _slow = null;
    if (widget.fallback == null) return;
    _slow = Timer(widget.fallbackDelay, () {
      if (mounted) setState(() => _showFallbackWhileLoading = true);
    });
  }

  @override
  void dispose() {
    _slow?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _effectiveProvider;
    final fallback = widget.fallback;
    if (provider == null) return fallback ?? const SizedBox.shrink();

    final image = Image(
      image: provider,
      fit: BoxFit.contain,
      frameBuilder: fallback == null
          ? null
          : (_, child, frame, wasSynchronouslyLoaded) {
              if (frame != null || wasSynchronouslyLoaded) return child;
              return _showFallbackWhileLoading
                  ? fallback
                  : const SizedBox.shrink();
            },
      errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.maxHeight,
        maxWidth: widget.maxWidth,
      ),
      child: Stack(
        alignment: fallback == null
            ? Alignment.center
            : AlignmentDirectional.centerStart,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 3,
              sigmaY: 3,
              tileMode: TileMode.decal,
            ),
            child: Image(
              image: provider,
              fit: BoxFit.contain,
              color: AppColorScheme.scrim.withValues(alpha: 0.6),
              colorBlendMode: BlendMode.srcATop,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          image,
        ],
      ),
    );
  }
}
