import 'package:flutter/material.dart';

import '../jolt_physics.dart'
    hide BoxShape, CapsuleShape, ColliderShape, CylinderShape, SphereShape;
import '../physics/collider_shape.dart' as physics;

/// Debug-only inspector for invisible Jolt collider shapes.
///
/// The map uses a stable top-down X/Z view so it remains useful while the
/// native Filament orbit camera is rotated independently.
final class PhysicsDebugOverlay extends StatelessWidget {
  /// Creates an overlay from live [bodies] snapshots.
  const PhysicsDebugOverlay({super.key, required this.bodies});

  /// Bodies captured from [PhysicsWorld.snapshotBodies].
  final List<RigidBodySnapshot> bodies;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xdd06111f),
          border: Border.all(color: const Color(0xff38bdf8)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'COLLIDERS  X / Z',
              style: TextStyle(
                color: Color(0xff7dd3fc),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 132,
              height: 96,
              child: CustomPaint(painter: _ColliderMapPainter(bodies)),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ColliderMapPainter extends CustomPainter {
  _ColliderMapPainter(this.bodies);

  final List<RigidBodySnapshot> bodies;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.shortestSide / 18;
    final gridPaint = Paint()
      ..color = const Color(0xff1e3a5f)
      ..strokeWidth = 1;
    for (var i = -8; i <= 8; i += 2) {
      canvas.drawLine(
        Offset(center.dx + i * scale, 0),
        Offset(center.dx + i * scale, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, center.dy + i * scale),
        Offset(size.width, center.dy + i * scale),
        gridPaint,
      );
    }
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      Paint()
        ..color = const Color(0xff3b82f6)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      Paint()
        ..color = const Color(0xffef4444)
        ..strokeWidth = 1.5,
    );

    for (final snapshot in bodies) {
      _drawBody(canvas, center, scale, snapshot);
    }
  }

  void _drawBody(
    Canvas canvas,
    Offset center,
    double scale,
    RigidBodySnapshot snapshot,
  ) {
    final body = snapshot.body;
    final position = snapshot.transform.position;
    final point = Offset(
      center.dx + position.x * scale,
      center.dy + position.z * scale,
    );
    final paint = Paint()
      ..color = _motionColor(body.settings.motionType)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final shape = body.settings.shape;
    if (shape is physics.BoxShape) {
      canvas.drawRect(
        Rect.fromCenter(
          center: point,
          width: shape.halfWidth * 2 * scale,
          height: shape.halfDepth * 2 * scale,
        ),
        paint,
      );
    } else if (shape is physics.SphereShape) {
      canvas.drawCircle(point, shape.radius * scale, paint);
    } else if (shape is physics.CapsuleShape) {
      canvas.drawCircle(point, shape.radius * scale, paint);
      canvas.drawCircle(
        point,
        (shape.radius + shape.halfHeight * 0.25) * scale,
        paint..strokeWidth = 1,
      );
    } else if (shape is physics.CylinderShape) {
      canvas.drawCircle(point, shape.radius * scale, paint);
      canvas.drawLine(
        point.translate(-shape.radius * scale, 0),
        point.translate(shape.radius * scale, 0),
        paint..strokeWidth = 1,
      );
    }
    final label = TextPainter(
      text: TextSpan(
        text: '#${body.id.value}',
        style: TextStyle(color: paint.color, fontSize: 7),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, point + const Offset(4, -13));
  }

  @override
  bool shouldRepaint(_ColliderMapPainter oldDelegate) => true;
}

Color _motionColor(MotionType motionType) => switch (motionType) {
  MotionType.static => const Color(0xff94a3b8),
  MotionType.kinematic => const Color(0xfffacc15),
  MotionType.dynamic => const Color(0xff22d3ee),
};
