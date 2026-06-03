import 'package:flutter/material.dart';

import '../jolt_physics.dart';
import '../scene/orbit_camera.dart';
import 'textured_mesh_painter.dart';
import 'textured_mesh_prototype.dart';

final class PhysicsScenePainter extends CustomPainter {
  PhysicsScenePainter({
    required this.cube,
    required this.camera,
    required this.meshPrototype,
  });

  final PhysicsTransform cube;
  final OrbitCamera camera;
  final TexturedMeshPrototype meshPrototype;

  static const _edges = [
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
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff07111f), Color(0xff102337)],
        ).createShader(Offset.zero & size),
    );
    _drawGrid(canvas, size);
    _drawTexturedMesh(canvas, size);
    _drawAxes(canvas, size);
    _drawCube(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff38bdf8).withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = -8; i <= 8; i++) {
      _drawWorldLine(
        canvas,
        size,
        Vector3(i.toDouble(), 0, -8),
        Vector3(i.toDouble(), 0, 8),
        paint,
      );
      _drawWorldLine(
        canvas,
        size,
        Vector3(-8, 0, i.toDouble()),
        Vector3(8, 0, i.toDouble()),
        paint,
      );
    }
  }

  void _drawAxes(Canvas canvas, Size size) {
    _drawAxis(
      canvas,
      size,
      const Vector3(3, 0, 0),
      'X',
      const Color(0xffef4444),
    );
    _drawAxis(
      canvas,
      size,
      const Vector3(0, 3, 0),
      'Y',
      const Color(0xff22c55e),
    );
    _drawAxis(
      canvas,
      size,
      const Vector3(0, 0, 3),
      'Z',
      const Color(0xff3b82f6),
    );
  }

  void _drawCube(Canvas canvas, Size size) {
    const half = 0.65;
    final corners = <Vector3>[
      for (final x in [-half, half])
        for (final y in [-half, half])
          for (final z in [-half, half])
            _rotate(Vector3(x, y, z)).translate(cube.x, cube.y, cube.z),
    ];
    final points = corners.map((point) => camera.project(point, size)).toList();
    final glowPaint = Paint()
      ..color = const Color(0xff38bdf8).withValues(alpha: 0.25)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final edgePaint = Paint()
      ..color = const Color(0xffe0f2fe)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final edge in _edges) {
      canvas.drawLine(points[edge[0]], points[edge[1]], glowPaint);
      canvas.drawLine(points[edge[0]], points[edge[1]], edgePaint);
    }
  }

  void _drawTexturedMesh(Canvas canvas, Size size) {
    drawTexturedMeshPrototype(
      canvas,
      size,
      mesh: meshPrototype,
      camera: camera,
      origin: const Vector3(-2.7, 0.04, 0.3),
    );
  }

  void _drawWorldLine(
    Canvas canvas,
    Size size,
    Vector3 start,
    Vector3 end,
    Paint paint,
  ) {
    canvas.drawLine(
      camera.project(start, size),
      camera.project(end, size),
      paint,
    );
  }

  void _drawAxis(
    Canvas canvas,
    Size size,
    Vector3 end,
    String label,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3;
    _drawWorldLine(canvas, size, const Vector3(0, 0, 0), end, paint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, camera.project(end, size) + const Offset(5, -10));
  }

  Vector3 _rotate(Vector3 point) {
    final ix = cube.qw * point.x + cube.qy * point.z - cube.qz * point.y;
    final iy = cube.qw * point.y + cube.qz * point.x - cube.qx * point.z;
    final iz = cube.qw * point.z + cube.qx * point.y - cube.qy * point.x;
    final iw = -cube.qx * point.x - cube.qy * point.y - cube.qz * point.z;
    return Vector3(
      ix * cube.qw + iw * -cube.qx + iy * -cube.qz - iz * -cube.qy,
      iy * cube.qw + iw * -cube.qy + iz * -cube.qx - ix * -cube.qz,
      iz * cube.qw + iw * -cube.qz + ix * -cube.qy - iy * -cube.qx,
    );
  }

  @override
  bool shouldRepaint(PhysicsScenePainter oldDelegate) =>
      oldDelegate.cube != cube ||
      oldDelegate.camera != camera ||
      oldDelegate.meshPrototype != meshPrototype;
}
