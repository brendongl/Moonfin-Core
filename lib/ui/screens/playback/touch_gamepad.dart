import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../util/core_input_descriptors.dart';
import '../../../util/touch_gamepad_layout.dart';

/// The native player's on-screen pad: one console shell per system, from
/// [touchPadLayoutFor]. A single Listener owns every finger, so a thumb can
/// slide between buttons, roll the d-pad through its diagonals, and hold a
/// stick while another finger taps.
class TouchGamepad extends StatefulWidget {
  const TouchGamepad({
    super.key,
    required this.core,
    required this.size,
    required this.safe,
    required this.pictureRect,
    required this.portrait,
    required this.inputDescriptors,
    required this.analogPorts,
    required this.padType,
    required this.onMask,
    required this.onSticks,
    required this.onPointer,
    required this.onMenu,
  });

  final String core;
  final Size size;
  final EdgeInsets safe;
  final Rect pictureRect;
  final bool portrait;
  final CoreInputDescriptors inputDescriptors;
  final int analogPorts;
  final int padType;

  /// The OR of every held button's RetroPad bits, on change.
  final ValueChanged<int> onMask;

  /// Left and right stick vectors on the unit circle, on change.
  final void Function(Offset left, Offset right) onSticks;

  /// A touch on the picture, normalised to -1..1 over the whole picture.
  final void Function(bool pressed, double x, double y) onPointer;
  final VoidCallback onMenu;

  @override
  State<TouchGamepad> createState() => _TouchGamepadState();
}

class _Touch {
  int index = -1;
  int bits = 0;
  Offset stick = Offset.zero;
  bool onPicture = false;
}

class _TouchGamepadState extends State<TouchGamepad> {
  final Map<int, _Touch> _touches = {};
  late TouchPadLayout _layout;
  late List<PlacedControl> _placed;
  int _mask = 0;
  Offset _left = Offset.zero;
  Offset _right = Offset.zero;

  @override
  void initState() {
    super.initState();
    _relayout();
  }

  @override
  void didUpdateWidget(TouchGamepad old) {
    super.didUpdateWidget(old);
    if (old.core != widget.core ||
        old.size != widget.size ||
        old.safe != widget.safe ||
        old.pictureRect != widget.pictureRect ||
        old.portrait != widget.portrait ||
        old.analogPorts != widget.analogPorts ||
        old.padType != widget.padType ||
        old.inputDescriptors != widget.inputDescriptors) {
      _relayout();
    }
  }

  void _relayout() {
    _layout = touchPadLayoutFor(
      widget.core,
      tall: widget.portrait,
      padType: widget.padType,
      analogPorts: widget.analogPorts,
    );
    _placed = placeTouchPad(
      _layout,
      widget.size,
      widget.safe,
      widget.pictureRect,
      portrait: widget.portrait,
    );
  }

  int _hit(Offset p) {
    for (var i = 0; i < _placed.length; i++) {
      final c = _placed[i];
      final inside = c.control.shape == TouchShape.circle
          ? (p - c.center).distance <= c.radius + 8
          : c.rect.inflate(6).contains(p);
      if (inside) return i;
    }
    return -1;
  }

  void _down(PointerDownEvent e) {
    final t = _Touch();
    _touches[e.pointer] = t;
    _track(t, e.localPosition, start: true);
  }

  void _move(PointerMoveEvent e) {
    final t = _touches[e.pointer];
    if (t != null) _track(t, e.localPosition);
  }

  void _up(int pointer) {
    final t = _touches.remove(pointer);
    if (t == null) return;
    if (t.onPicture) widget.onPointer(false, 0, 0);
    _publish();
  }

  void _track(_Touch t, Offset p, {bool start = false}) {
    // Buttons re-hit-test so a slide reaches the neighbour. A d-pad or stick
    // keeps its finger until it lifts, however far it roams.
    final owner = t.index < 0 ? null : _placed[t.index].control;
    if (start || owner == null || owner.kind == TouchControlKind.button) {
      final i = _hit(p);
      t.index = i;
      if (i < 0 && start && _layout.touchScreen) {
        t.onPicture = widget.pictureRect.contains(p);
      }
    }
    if (t.onPicture) {
      final r = widget.pictureRect;
      widget.onPointer(
        true,
        ((p.dx - r.left) / r.width * 2 - 1).clamp(-1.0, 1.0),
        ((p.dy - r.top) / r.height * 2 - 1).clamp(-1.0, 1.0),
      );
      return;
    }
    t.bits = 0;
    t.stick = Offset.zero;
    if (t.index >= 0) {
      final c = _placed[t.index];
      switch (c.control.kind) {
        case TouchControlKind.button:
          t.bits = c.control.mask;
        case TouchControlKind.dpad:
          t.bits = dpadBitsFor(
            p - c.center,
            c.radius * 0.18,
            c.control.dpadIds,
          );
        case TouchControlKind.stick:
          final v = stickVector(p - c.center, c.radius * 0.7);
          if (c.control.digital) {
            t.bits = dpadBitsFor(v, 0.25, c.control.dpadIds);
          } else {
            t.stick = v;
          }
        case TouchControlKind.menu:
          if (start) widget.onMenu();
      }
    }
    _publish();
  }

  void _publish() {
    var mask = 0;
    var left = Offset.zero;
    var right = Offset.zero;
    for (final t in _touches.values) {
      mask |= t.bits;
      if (t.index < 0) continue;
      final c = _placed[t.index].control;
      if (c.kind != TouchControlKind.stick || c.digital) continue;
      if (c.rightStick) {
        right = t.stick;
      } else {
        left = t.stick;
      }
    }
    if (mask != _mask) {
      if (mask & ~_mask != 0) HapticFeedback.selectionClick();
      _mask = mask;
      widget.onMask(mask);
    }
    if (left != _left || right != _right) {
      _left = left;
      _right = right;
      widget.onSticks(left, right);
    }
    if (mounted) setState(() {});
  }

  String _label(TouchControl c) {
    final id = c.id;
    if (id == null) return c.label;
    // The core's label replaces the shell's only when it fits a button, long
    // ones like "Left Difficulty A" keep the shell's short form.
    final own =
        widget.inputDescriptors.describe(0, id, device: widget.padType) ??
        widget.inputDescriptors.describe(0, id);
    return own != null && own.length <= 6 ? own : c.label;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (e) => _up(e.pointer),
      onPointerCancel: (e) => _up(e.pointer),
      child: IgnorePointer(
        child: CustomPaint(
          size: widget.size,
          painter: _PadPainter(
            placed: _placed,
            layout: _layout,
            mask: _mask,
            left: _left,
            right: _right,
            labelOf: _label,
          ),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({
    required this.placed,
    required this.layout,
    required this.mask,
    required this.left,
    required this.right,
    required this.labelOf,
  });

  final List<PlacedControl> placed;
  final TouchPadLayout layout;
  final int mask;
  final Offset left;
  final Offset right;
  final String Function(TouchControl) labelOf;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in placed) {
      switch (p.control.kind) {
        case TouchControlKind.button:
          _button(canvas, p);
        case TouchControlKind.dpad:
          _dpad(canvas, p);
        case TouchControlKind.stick:
          _stick(canvas, p);
        case TouchControlKind.menu:
          _menu(canvas, p);
      }
    }
  }

  Paint _stroke(double alpha, [double width = 1.5]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = Colors.white.withValues(alpha: alpha);

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize, {
    double letterSpacing = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _button(Canvas canvas, PlacedControl p) {
    final c = p.control;
    final held = c.mask != 0 && mask & c.mask == c.mask;
    switch (c.shape) {
      case TouchShape.circle:
        final r = p.radius;
        canvas.drawCircle(
          p.center,
          r,
          Paint()..color = c.color.withValues(alpha: held ? 0.95 : 0.72),
        );
        canvas.drawCircle(p.center, r, _stroke(held ? 0.9 : 0.42));
        canvas.drawCircle(
          p.center - Offset(0, r * 0.18),
          r * 0.72,
          Paint()..color = Colors.white.withValues(alpha: 0.07),
        );
        if (c.glyph != null) {
          _glyph(canvas, c.glyph!, p.center, r);
        } else {
          final label = labelOf(c);
          _text(
            canvas,
            label,
            p.center,
            label.length > 2 ? r * 0.56 : r * 0.78,
          );
        }
      case TouchShape.tab:
        final rect = RRect.fromRectAndRadius(p.rect, const Radius.circular(13));
        canvas.drawRRect(
          rect,
          Paint()..color = c.color.withValues(alpha: held ? 0.95 : 0.66),
        );
        canvas.drawRRect(rect, _stroke(held ? 0.9 : 0.4));
        _text(canvas, labelOf(c), p.center, 17);
      case TouchShape.pill:
        final rect = RRect.fromRectAndRadius(p.rect, const Radius.circular(14));
        canvas.drawRRect(
          rect,
          Paint()
            ..color = layout.pillColor.withValues(alpha: held ? 0.95 : 0.72),
        );
        canvas.drawRRect(rect, _stroke(held ? 0.9 : 0.35, 1.2));
        _text(canvas, labelOf(c), p.center, 11, letterSpacing: 1.2);
    }
  }

  void _glyph(Canvas canvas, String kind, Offset c, double r) {
    final g = r * 0.42;
    final paint = _stroke(1, math.max(2.4, r * 0.11));
    switch (kind) {
      case 'tri':
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - g)
            ..lineTo(c.dx + g * 0.95, c.dy + g * 0.62)
            ..lineTo(c.dx - g * 0.95, c.dy + g * 0.62)
            ..close(),
          paint,
        );
      case 'cir':
        canvas.drawCircle(c, g * 0.85, paint);
      case 'x':
        canvas.drawLine(
          c + Offset(-g * 0.75, -g * 0.75),
          c + Offset(g * 0.75, g * 0.75),
          paint,
        );
        canvas.drawLine(
          c + Offset(g * 0.75, -g * 0.75),
          c + Offset(-g * 0.75, g * 0.75),
          paint,
        );
      default:
        canvas.drawRect(
          Rect.fromCenter(center: c, width: g * 1.44, height: g * 1.44),
          paint,
        );
    }
  }

  void _chevron(Canvas canvas, Offset c, Offset dir, double s, Paint paint) {
    // dir is the unit direction the arrow points, the two wings sit behind it.
    final side = Offset(-dir.dy, dir.dx);
    canvas.drawPath(
      Path()
        ..moveTo(
          c.dx - dir.dx * s / 2 + side.dx * s,
          c.dy - dir.dy * s / 2 + side.dy * s,
        )
        ..lineTo(c.dx + dir.dx * s / 2, c.dy + dir.dy * s / 2)
        ..lineTo(
          c.dx - dir.dx * s / 2 - side.dx * s,
          c.dy - dir.dy * s / 2 - side.dy * s,
        ),
      paint,
    );
  }

  static const _dirs = [
    Offset(0, -1),
    Offset(0, 1),
    Offset(-1, 0),
    Offset(1, 0),
  ];

  void _dpad(Canvas canvas, PlacedControl p) {
    final c = p.control, size = p.rect.width, h = size / 2;
    final a = size * 0.34, t = a / 2, cx = p.center.dx, cy = p.center.dy;
    final cross = Path()
      ..moveTo(cx - t, cy - h)
      ..relativeLineTo(a, 0)
      ..relativeLineTo(0, h - t)
      ..relativeLineTo(h - t, 0)
      ..relativeLineTo(0, a)
      ..relativeLineTo(-(h - t), 0)
      ..relativeLineTo(0, h - t)
      ..relativeLineTo(-a, 0)
      ..relativeLineTo(0, -(h - t))
      ..relativeLineTo(-(h - t), 0)
      ..relativeLineTo(0, -a)
      ..relativeLineTo(h - t, 0)
      ..close();
    canvas.drawPath(cross, Paint()..color = c.color.withValues(alpha: 0.66));
    canvas.drawPath(cross, _stroke(0.38));
    canvas.drawCircle(
      p.center,
      a * 0.26,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    final off = size * 0.36;
    for (final (i, d) in _dirs.indexed) {
      final held = mask & (1 << c.dpadIds[i]) != 0;
      final at = p.center + d * off;
      if (held) {
        canvas.drawCircle(
          at,
          a * 0.42,
          Paint()..color = Colors.white.withValues(alpha: 0.28),
        );
      }
      _chevron(canvas, at, d, a * 0.16, _stroke(held ? 1 : 0.7, 2.4));
    }
  }

  void _stick(Canvas canvas, PlacedControl p) {
    final r = p.radius;
    canvas.drawCircle(
      p.center,
      r,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    canvas.drawCircle(p.center, r, _stroke(0.6, 1.6));
    final ring = _stroke(0.18, 1);
    for (var i = 0; i < 24; i++) {
      final a0 = i * math.pi / 12;
      canvas.drawArc(
        Rect.fromCircle(center: p.center, radius: r * 0.66),
        a0,
        math.pi / 36,
        false,
        ring,
      );
    }
    final v = p.control.digital
        ? Offset.zero
        : (p.control.rightStick ? right : left);
    final knob = p.center + v * (r * 0.5);
    canvas.drawCircle(
      knob,
      r * 0.42,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawCircle(knob, r * 0.42, _stroke(0.7, 1.6));
  }

  void _menu(Canvas canvas, PlacedControl p) {
    canvas.drawCircle(
      p.center,
      p.radius,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawCircle(p.center, p.radius, _stroke(0.35, 1.2));
    for (final dy in const [-5.5, 0.0, 5.5]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: p.center + Offset(0, dy),
            width: 16,
            height: 2.5,
          ),
          const Radius.circular(1),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.placed != placed ||
      old.mask != mask ||
      old.left != left ||
      old.right != right;
}
