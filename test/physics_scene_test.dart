import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/scene/physics_scene.dart';

void main() {
  test('demo tap ray reports the model collider hit', () {
    final scene = PhysicsScene();
    addTearDown(scene.dispose);

    scene.castRayAtModel();

    expect(scene.touchStatus, 'Touched grass');
  });
}
