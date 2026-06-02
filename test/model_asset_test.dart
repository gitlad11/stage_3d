import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/jolt_physics.dart';
import 'package:stage_3d/jolt_rendering.dart';

void main() {
  test('ModelAsset serializes GLB renderer settings', () {
    const asset = ModelAsset(
      assetPath: 'models/room.glb',
      normalizedScale: 2,
      animationIndex: 1,
    );

    expect(asset.toMessage(), {
      'assetPath': 'models/room.glb',
      'normalizedScale': 2,
      'animationIndex': 1,
    });
  });

  test('RenderModelController retains the latest instance transform', () {
    final models = RenderModelController();
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/room.glb'),
    );
    final instance = models.createInstance(
      asset,
      transform: const PhysicsTransform(position: Vector3(1, 0, 2)),
    );

    const updated = PhysicsTransform(position: Vector3(3, 0, 4));
    models.setTransform(instance, updated);

    expect(instance.transform, same(updated));
  });

  test('ModelAnimation reads native clip metadata', () {
    final animation = ModelAnimation.fromMessage({
      'index': 2,
      'name': 'Walk',
      'durationSeconds': 1.5,
    });

    expect(animation.index, 2);
    expect(animation.name, 'Walk');
    expect(animation.durationSeconds, 1.5);
  });

  test('RenderModelController retains animation playback state', () {
    final models = RenderModelController();
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/character.glb'),
    );
    final instance = models.createInstance(
      asset,
      transform: const PhysicsTransform(position: Vector3.zero),
    );

    models.playAnimation(instance, animationIndex: 1, speed: 1.5);
    expect(instance.animation?.animationIndex, 1);
    expect(instance.animation?.speed, 1.5);

    models.pauseAnimation(instance);
    expect(instance.animation?.paused, isTrue);

    models.resumeAnimation(instance);
    expect(instance.animation?.paused, isFalse);

    models.stopAnimation(instance);
    expect(instance.animation, isNull);
  });
}
