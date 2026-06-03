import 'package:flutter/material.dart';

import '../physics/vector3.dart';
import '../scene/orbit_camera.dart';
import 'textured_mesh_prototype.dart';

/// Draws a [TexturedMeshPrototype] into the Flutter preview/overlay canvas.
void drawTexturedMeshPrototype(
  Canvas canvas,
  Size size, {
  required TexturedMeshPrototype mesh,
  required OrbitCamera camera,
  Vector3 origin = Vector3.zero,
}) {
  final projected = [
    for (final vertex in mesh.vertices)
      camera.project(
        vertex.position.translate(origin.x, origin.y, origin.z),
        size,
      ),
  ];
  for (var i = 0; i < mesh.indices.length; i += 3) {
    final a = mesh.indices[i];
    final b = mesh.indices[i + 1];
    final c = mesh.indices[i + 2];
    final centroidUv =
        (mesh.vertices[a].uv + mesh.vertices[b].uv + mesh.vertices[c].uv) / 3;
    final path = Path()
      ..moveTo(projected[a].dx, projected[a].dy)
      ..lineTo(projected[b].dx, projected[b].dy)
      ..lineTo(projected[c].dx, projected[c].dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = _textureColorAt(mesh, centroidUv).withValues(alpha: 0.82)
        ..style = PaintingStyle.fill,
    );
  }

  final edgePaint = Paint()
    ..color = const Color(0xffecfeff).withValues(alpha: 0.9)
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (var i = 0; i < mesh.indices.length; i += 3) {
    final a = projected[mesh.indices[i]];
    final b = projected[mesh.indices[i + 1]];
    final c = projected[mesh.indices[i + 2]];
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..close(),
      edgePaint,
    );
  }
}

Color _textureColorAt(TexturedMeshPrototype mesh, Offset uv) {
  final texture = mesh.texture;
  final tile =
      (uv.dx * texture.repeatU).floor() + (uv.dy * texture.repeatV).floor();
  return tile.isEven ? texture.primaryColor : texture.secondaryColor;
}

/// Transparent overlay used to show mesh prototypes above native Filament.
final class TexturedMeshOverlayPainter extends CustomPainter {
  const TexturedMeshOverlayPainter({
    required this.mesh,
    required this.camera,
    this.origin = const Vector3(-2.7, 0.04, 0.3),
  });

  final TexturedMeshPrototype mesh;
  final OrbitCamera camera;
  final Vector3 origin;

  @override
  void paint(Canvas canvas, Size size) {
    drawTexturedMeshPrototype(
      canvas,
      size,
      mesh: mesh,
      camera: camera,
      origin: origin,
    );
  }

  @override
  bool shouldRepaint(TexturedMeshOverlayPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.camera != camera ||
      oldDelegate.origin != origin;
}
