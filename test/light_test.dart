import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/jolt_physics.dart';
import 'package:stage_3d/rendering/light.dart';

void main() {
  test('DirectionalLight serializes renderer settings', () {
    const light = DirectionalLight(
      direction: Vector3(0, -1, 0),
      intensity: 120000,
    );

    expect(light.toMessage(), {
      'type': 0,
      'dx': 0,
      'dy': -1,
      'dz': 0,
      'r': 1,
      'g': 1,
      'b': 1,
      'intensity': 120000,
      'castShadows': true,
    });
  });

  test('PointLight serializes movable renderer settings', () {
    const light = PointLight(
      position: Vector3(2, 4, 1),
      intensity: 1500,
      falloffRadius: 8,
    );

    expect(light.toMessage(), {
      'type': 1,
      'x': 2,
      'y': 4,
      'z': 1,
      'r': 1,
      'g': 1,
      'b': 1,
      'intensity': 1500,
      'falloffRadius': 8,
      'castShadows': true,
    });
  });
}
