import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Normalized two-axis joystick value in the `-1..1` range.
final class JoystickValue {
  /// Creates a joystick value.
  const JoystickValue(this.x, this.y);

  /// Centered joystick value.
  static const zero = JoystickValue(0, 0);

  /// Horizontal axis, where left is `-1` and right is `1`.
  final double x;

  /// Vertical axis, where up is `-1` and down is `1`.
  final double y;

  /// Distance from the center in the `0..1` range.
  double get magnitude => math.sqrt(x * x + y * y).clamp(0, 1);

  @override
  bool operator ==(Object other) =>
      other is JoystickValue && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Controller that exposes the latest [VirtualJoystick] value to listeners.
final class VirtualJoystickController extends ValueNotifier<JoystickValue> {
  /// Creates a centered joystick controller.
  VirtualJoystickController() : super(JoystickValue.zero);

  /// Returns the joystick to its centered value.
  void reset() {
    value = JoystickValue.zero;
  }
}

/// Reusable two-axis joystick built entirely with Flutter widgets and painting.
///
/// The joystick does not know what it controls. Consumers listen to
/// [controller] and apply its normalized value to a camera, character, vehicle,
/// or any other interactive object.
class VirtualJoystick extends StatefulWidget {
  /// Creates a virtual joystick.
  const VirtualJoystick({
    super.key,
    required this.controller,
    this.size = 116,
    this.deadZone = 0.08,
    this.baseColor = const Color(0xbb071527),
    this.accentColor = const Color(0xff7dd3fc),
  }) : assert(size > 0),
       assert(deadZone >= 0 && deadZone < 1);

  /// Receives normalized joystick values.
  final VirtualJoystickController controller;

  /// Square joystick size.
  final double size;

  /// Center area that produces a zero value.
  final double deadZone;

  /// Background and border color basis.
  final Color baseColor;

  /// Active thumb and direction color.
  final Color accentColor;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _thumb = Offset.zero;

  void _update(Offset localPosition) {
    final radius = widget.size / 2;
    final local = localPosition - Offset(radius, radius);
    final distance = local.distance;
    final constrained = distance > radius ? local / distance * radius : local;
    final normalized = constrained / radius;
    final magnitude = normalized.distance;
    final value = magnitude < widget.deadZone
        ? JoystickValue.zero
        : JoystickValue(normalized.dx, normalized.dy);
    setState(() => _thumb = constrained);
    widget.controller.value = value;
  }

  void _reset() {
    setState(() => _thumb = Offset.zero);
    widget.controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Virtual joystick',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) => _update(details.localPosition),
        onPanUpdate: (details) => _update(details.localPosition),
        onPanEnd: (_) => _reset(),
        onPanCancel: _reset,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _VirtualJoystickPainter(
              thumb: _thumb,
              baseColor: widget.baseColor,
              accentColor: widget.accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

final class _VirtualJoystickPainter extends CustomPainter {
  const _VirtualJoystickPainter({
    required this.thumb,
    required this.baseColor,
    required this.accentColor,
  });

  final Offset thumb;
  final Color baseColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius - 1, Paint()..color = baseColor);
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = accentColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      center,
      radius * 0.42,
      Paint()
        ..color = accentColor.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      center,
      center + thumb,
      Paint()
        ..color = accentColor.withValues(alpha: 0.35)
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      center + thumb,
      radius * 0.28,
      Paint()..color = accentColor.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_VirtualJoystickPainter oldDelegate) =>
      oldDelegate.thumb != thumb ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.accentColor != accentColor;
}
