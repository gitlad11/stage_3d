import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../jolt_physics.dart'
    hide
        BoxShape,
        CapsuleShape,
        ColliderShape,
        CompoundShape,
        CylinderShape,
        PositionedShape,
        SphereShape;
import '../physics/collider_shape.dart' as physics;
import '../scene/orbit_camera.dart';

/// Draws Jolt collider shapes as a wireframe overlay in the active viewport.
final class PhysicsColliderDebugPainter extends CustomPainter {
  /// Creates a collider debug painter from rigid body snapshots.
  const PhysicsColliderDebugPainter({
    required this.bodies,
    required this.camera,
    this.color = const Color(0xff050505),
  });

  /// Bodies captured from [PhysicsWorld.snapshotBodies].
  final List<RigidBodySnapshot> bodies;

  /// Camera used to project world points into the overlay.
  final OrbitCamera camera;

  /// Wireframe color.
  final Color color;

  static const _boxEdges = [
    [0, 1],
    [1, 3],
    [3, 2],
    [2, 0],
    [4, 5],
    [5, 7],
    [7, 6],
    [6, 4],
    [0, 4],
    [1, 5],
    [2, 6],
    [3, 7],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final glow = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final snapshot in bodies) {
      _drawShape(
        canvas,
        size,
        snapshot.body.settings.shape,
        snapshot.transform,
        Vector3.zero,
        Quaternion.identity,
        glow,
        paint,
      );
    }
  }

  void _drawShape(
    Canvas canvas,
    Size size,
    physics.ColliderShape shape,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
    Paint glow,
    Paint paint,
  ) {
    switch (shape) {
      case physics.BoxShape():
        _drawBox(
          canvas,
          size,
          shape,
          transform,
          localPosition,
          localRotation,
          glow,
          paint,
        );
      case physics.SphereShape():
        _drawSphere(
          canvas,
          size,
          shape.radius,
          transform,
          localPosition,
          localRotation,
          glow,
          paint,
        );
      case physics.CapsuleShape():
        _drawCapsule(
          canvas,
          size,
          shape,
          transform,
          localPosition,
          localRotation,
          glow,
          paint,
        );
      case physics.CylinderShape():
        _drawCylinder(
          canvas,
          size,
          shape,
          transform,
          localPosition,
          localRotation,
          glow,
          paint,
        );
      case physics.CompoundShape():
        for (final child in shape.children) {
          _drawShape(
            canvas,
            size,
            child.shape,
            transform,
            child.position,
            child.rotation,
            glow,
            paint,
          );
        }
    }
  }

  void _drawBox(
    Canvas canvas,
    Size size,
    physics.BoxShape shape,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
    Paint glow,
    Paint paint,
  ) {
    final corners = <Vector3>[
      for (final x in [-shape.halfWidth, shape.halfWidth])
        for (final y in [-shape.halfHeight, shape.halfHeight])
          for (final z in [-shape.halfDepth, shape.halfDepth])
            _worldPoint(
              Vector3(x, y, z),
              transform,
              localPosition,
              localRotation,
            ),
    ];
    final points = corners.map((point) => camera.project(point, size)).toList();
    for (final edge in _boxEdges) {
      canvas.drawLine(points[edge[0]], points[edge[1]], glow);
      canvas.drawLine(points[edge[0]], points[edge[1]], paint);
    }
  }

  void _drawSphere(
    Canvas canvas,
    Size size,
    double radius,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
    Paint glow,
    Paint paint,
  ) {
    _drawCircle(
      canvas,
      size,
      radius,
      _Axis.xy,
      transform,
      localPosition,
      localRotation,
      glow,
      paint,
    );
    _drawCircle(
      canvas,
      size,
      radius,
      _Axis.xz,
      transform,
      localPosition,
      localRotation,
      glow,
      paint,
    );
    _drawCircle(
      canvas,
      size,
      radius,
      _Axis.yz,
      transform,
      localPosition,
      localRotation,
      glow,
      paint,
    );
  }

  void _drawCapsule(
    Canvas canvas,
    Size size,
    physics.CapsuleShape shape,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
    Paint glow,
    Paint paint,
  ) {
    _drawSphere(
      canvas,
      size,
      shape.radius,
      transform,
      localPosition.translate(0, shape.halfHeight, 0),
      localRotation,
      glow,
      paint,
    );
    _drawSphere(
      canvas,
      size,
      shape.radius,
      transform,
      localPosition.translate(0, -shape.halfHeight, 0),
      localRotation,
      glow,
      paint,
    );
    for (final offset in [
      Vector3(shape.radius, 0, 0),
      Vector3(-shape.radius, 0, 0),
      Vector3(0, 0, shape.radius),
      Vector3(0, 0, -shape.radius),
    ]) {
      _drawLine(
        canvas,
        size,
        Vector3(offset.x, shape.halfHeight, offset.z),
        Vector3(offset.x, -shape.halfHeight, offset.z),
        transform,
        localPosition,
        localRotation,
        glow,
        paint,
      );
    }
  }

  void _drawCylinder(
    Canvas canvas,
    Size size,
    physics.CylinderShape shape,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
    Paint glow,
    Paint paint,
  ) {
    _drawCircle(
      canvas,
      size,
      shape.radius,
      _Axis.xz,
      transform,
      localPosition.translate(0, shape.halfHeight, 0),
      localRotation,
      glow,
      paint,
    );
    _drawCircle(
      canvas,
      size,
      shape.radius,
      _Axis.xz,
      transform,
      localPosition.translate(0, -shape.halfHeight, 0),
      localRotation,
      glow,
      paint,
    );
    for (final offset in [
      Vector3(shape.radius, 0, 0),
      Vector3(-shape.radius, 0, 0),
      Vector3(0, 0, shape.radius),
      Vector3(0, 0, -shape.radius),
    ]) {
      _drawLine(
        canvas,
        size,
        Vector3(offset.x, shape.halfHeight, offset.z),
        Vector3(offset.x, -shape.halfHeight, offset.z),
        transform,
        localPosition,
        localRotation,
        glow,
        paint,
      );
    }
  }

  void _drawCircle(
    Canvas canvas,
    Size size,
    double radius,
    _Axis axis,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
    Paint glow,
    Paint paint,
  ) {
    const segments = 40;
    final points = <Offset>[];
    for (var i = 0; i <= segments; i++) {
      final angle = i / segments * math.pi * 2;
      final x = math.cos(angle) * radius;
      final y = math.sin(angle) * radius;
      final local = switch (axis) {
        _Axis.xy => Vector3(x, y, 0),
        _Axis.xz => Vector3(x, 0, y),
        _Axis.yz => Vector3(0, x, y),
      };
      points.add(
        camera.project(
          _worldPoint(local, transform, localPosition, localRotation),
          size,
        ),
      );
    }
    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], glow);
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    Vector3 start,
    Vector3 end,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
    Paint glow,
    Paint paint,
  ) {
    final a = camera.project(
      _worldPoint(start, transform, localPosition, localRotation),
      size,
    );
    final b = camera.project(
      _worldPoint(end, transform, localPosition, localRotation),
      size,
    );
    canvas.drawLine(a, b, glow);
    canvas.drawLine(a, b, paint);
  }

  Vector3 _worldPoint(
    Vector3 point,
    PhysicsTransform transform,
    Vector3 localPosition,
    Quaternion localRotation,
  ) {
    final childPoint = _rotate(
      point,
      localRotation,
    ).translate(localPosition.x, localPosition.y, localPosition.z);
    final bodyPoint = _rotate(childPoint, transform.rotation);
    return bodyPoint.translate(
      transform.position.x,
      transform.position.y,
      transform.position.z,
    );
  }

  Vector3 _rotate(Vector3 point, Quaternion rotation) {
    final ix =
        rotation.w * point.x + rotation.y * point.z - rotation.z * point.y;
    final iy =
        rotation.w * point.y + rotation.z * point.x - rotation.x * point.z;
    final iz =
        rotation.w * point.z + rotation.x * point.y - rotation.y * point.x;
    final iw =
        -rotation.x * point.x - rotation.y * point.y - rotation.z * point.z;
    return Vector3(
      ix * rotation.w + iw * -rotation.x + iy * -rotation.z - iz * -rotation.y,
      iy * rotation.w + iw * -rotation.y + iz * -rotation.x - ix * -rotation.z,
      iz * rotation.w + iw * -rotation.z + ix * -rotation.y - iy * -rotation.x,
    );
  }

  @override
  bool shouldRepaint(PhysicsColliderDebugPainter oldDelegate) =>
      oldDelegate.bodies != bodies ||
      oldDelegate.camera != camera ||
      oldDelegate.color != color;
}

enum _Axis { xy, xz, yz }
