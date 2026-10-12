import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import 'loading_animation_widget.dart';

class PlayerLoadingOverlay extends StatefulWidget {
  const PlayerLoadingOverlay({
    super.key,
    this.label,
    this.labelSpacing,
    this.customImage,
    this.customSize,
    this.customPosition,
    this.customShowText,
    this.customSpeed,
    this.flipHorizontal,
    this.steps = const <String>[],
    this.detail,
  });

  final String? label;
  final double? labelSpacing;
  final LoadingAnimationImage? customImage;
  final double? customSize;
  final LoadingAnimationPosition? customPosition;
  final bool? customShowText;
  final LoadingAnimationSpeed? customSpeed;
  final bool? flipHorizontal;

  /// Steps already finished, oldest first. Drawn dim with a tick above the
  /// current label so a customer reading the screen down the phone can tell
  /// support how far it got — the whole point of making these verbose.
  final List<String> steps;

  /// One line of context under the label (route, play method, elapsed).
  final String? detail;

  @override
  State<PlayerLoadingOverlay> createState() => _PlayerLoadingOverlayState();
}

class _PlayerLoadingOverlayState extends State<PlayerLoadingOverlay>
    with SingleTickerProviderStateMixin {
  static const _labelGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFAA5CC3), Color(0xFF00A4DC)],
  );

  late final AnimationController _labelController;
  late final Animation<double> _labelOpacity;
  late final Animation<double> _labelScale;

  @override
  void initState() {
    super.initState();
    _labelController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    final pulseCurve = CurvedAnimation(
      parent: _labelController,
      curve: Curves.easeInOut,
    );
    _labelOpacity = Tween<double>(begin: 0.4, end: 1.0).animate(pulseCurve);
    _labelScale = Tween<double>(begin: 0.98, end: 1.0).animate(pulseCurve);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = GetIt.instance.isRegistered<UserPreferences>()
        ? GetIt.instance<UserPreferences>()
        : null;

    final image = widget.customImage ??
        prefs?.get(UserPreferences.loadingAnimationImage) ??
        LoadingAnimationImage.moonfinLogo;

    final sizePref = prefs?.get(UserPreferences.loadingAnimationSize) ??
        LoadingAnimationSize.medium;

    final effectiveSize = widget.customSize ?? sizePref.pixelSize;

    final effectivePosition = widget.customPosition ??
        prefs?.get(UserPreferences.loadingAnimationPosition) ??
        LoadingAnimationPosition.middle;

    final showText = widget.customShowText ??
        prefs?.get(UserPreferences.showLoadingAnimationText) ??
        true;

    final effectiveSpeed = widget.customSpeed ??
        prefs?.get(UserPreferences.loadingAnimationSpeed) ??
        LoadingAnimationSpeed.fast;

    final label = widget.label?.trim();
    final hasLabel = showText && label != null && label.isNotEmpty;
    final uppercaseLabel = hasLabel ? label.toUpperCase() : null;

    if (image == LoadingAnimationImage.none && !hasLabel) {
      return const SizedBox.shrink();
    }

    final spacing = widget.labelSpacing ?? sizePref.labelSpacing;
    final fontSize = sizePref.labelFontSize;
    final letterSpacing = sizePref.labelLetterSpacing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (image == LoadingAnimationImage.moonfinLogo)
          // Sipflix fork: the default logo animation shows the Sipflix badge
          // (gentle wobble) instead of the Moonfin moon.
          RepaintBoundary(
            child: _SipflixBadgeAnimation(
              size: effectiveSize,
              speed: effectiveSpeed,
            ),
          )
        else if (image != LoadingAnimationImage.none)
          // Repaints every frame, so it gets a layer of its own.
          RepaintBoundary(
            child: LoadingAnimationWidget(
              image: image,
              size: effectiveSize,
              position: effectivePosition,
              flipHorizontal: widget.flipHorizontal,
              speed: effectiveSpeed,
            ),
          ),
        if (hasLabel) ...[
          if (image != LoadingAnimationImage.none) SizedBox(height: spacing),
          // Sipflix fork: finished bring-up steps, dim, above the live one.
          if (widget.steps.isNotEmpty) ...[
            for (final step in widget.steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '✓  $step',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
          FadeTransition(
            opacity: _labelOpacity,
            child: ScaleTransition(
              scale: _labelScale,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return _labelGradient.createShader(bounds);
                },
                child: Text(
                  uppercaseLabel!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: letterSpacing,
                  ),
                ),
              ),
            ),
          ),
          if (widget.detail != null && widget.detail!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.detail!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.5,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Sipflix fork: the branded loader, a Sipflix badge rocking on its Y axis.
class _SipflixBadgeAnimation extends StatefulWidget {
  const _SipflixBadgeAnimation({required this.size, required this.speed});

  final double size;
  final LoadingAnimationSpeed speed;

  @override
  State<_SipflixBadgeAnimation> createState() => _SipflixBadgeAnimationState();
}

class _SipflixBadgeAnimationState extends State<_SipflixBadgeAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Duration get _duration =>
      Duration(milliseconds: (8000 / widget.speed.multiplier).round());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: _duration, vsync: this)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant _SipflixBadgeAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _controller.duration = _duration;
      if (_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(math.sin(_controller.value * 2 * math.pi) * 0.32),
          child: child,
        );
      },
      child: Image.asset(
        'assets/images/sipflix_badge.png',
        width: widget.size,
        height: widget.size,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}
