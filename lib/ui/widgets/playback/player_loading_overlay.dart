import 'dart:math' as math;

import 'package:flutter/material.dart';

class PlayerLoadingOverlay extends StatefulWidget {
  const PlayerLoadingOverlay({
    super.key,
    this.label,
    this.logoSize = 180,
    this.labelSpacing = 60,
    this.steps = const <String>[],
    this.detail,
  });

  final String? label;
  final double logoSize;
  final double labelSpacing;

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
    with TickerProviderStateMixin {
  static const _labelGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFAA5CC3), Color(0xFF00A4DC)],
  );

  late final AnimationController _logoController;
  late final AnimationController _labelController;
  late final Animation<double> _labelOpacity;
  late final Animation<double> _labelScale;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
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
    _logoController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label?.trim();
    final hasLabel = label != null && label.isNotEmpty;
    final uppercaseLabel = hasLabel ? label.toUpperCase() : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _logoController,
          builder: (context, child) {
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(
                  math.sin(_logoController.value * 2 * math.pi) * 0.32,
                ),
              child: child,
            );
          },
          // Sipflix: branded loader shows the Sipflix badge instead of the moon.
          child: Image.asset(
            'assets/images/sipflix_badge.png',
            width: widget.logoSize,
            height: widget.logoSize,
            filterQuality: FilterQuality.medium,
          ),
        ),
        if (hasLabel) ...[
          SizedBox(height: widget.labelSpacing),
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
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
