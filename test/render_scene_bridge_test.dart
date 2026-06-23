import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/jolt_physics.dart';
import 'package:stage_3d/jolt_rendering.dart';

void main() {
  test('RenderModelController sends model operations through bridge', () async {
    final bridge = _RecordingBridge();
    final models = RenderModelController()..attachBridge(bridge);
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/room.glb'),
    );
    final instance = models.createInstance(
      asset,
      transform: const PhysicsTransform(position: Vector3(1, 0, 2)),
    );

    models.setTransform(
      instance,
      const PhysicsTransform(position: Vector3(3, 0, 4)),
    );
    models.playAnimation(instance, animationIndex: 1);

    expect(bridge.events, [
      'loadAsset:1',
      'createInstance:1',
      'setTransform:1',
      'playAnimation:1',
    ]);
  });

  test('RenderLightController sends light operations through bridge', () {
    final bridge = _RecordingBridge();
    final lights = RenderLightController()..attachBridge(bridge);
    final light = lights.createLight(
      const PointLight(position: Vector3(0, 1, 2)),
    );

    lights.setPosition(light, const Vector3(3, 4, 5));
    lights.setIntensity(light, 2000);
    lights.destroyLight(light);

    expect(bridge.events, [
      'createLight:1',
      'setLightPosition:1',
      'setLightIntensity:1',
      'destroyLight:1',
    ]);
  });

  test(
    'RenderEnvironmentController sends environment settings through bridge',
    () {
      final bridge = _RecordingBridge();
      final environment = RenderEnvironmentController(
        initialEnvironment: const RenderEnvironment(
          skyColor: Vector3(0.2, 0.4, 0.8),
          reflectionIntensity: 0.75,
        ),
      )..attachBridge(bridge);

      environment.setEnvironment(
        const RenderEnvironment(
          skyColor: Vector3(0.4, 0.8, 0.9),
          reflectionIntensity: 0.95,
        ),
      );

      expect(bridge.events, ['setEnvironment', 'setEnvironment']);
    },
  );

  test('FilamentViewportController sends camera presets through bridge', () {
    final bridge = _RecordingBridge();
    final viewport = FilamentViewportController()..attachBridge(bridge);

    viewport.setCamera(
      const StageCamera.orbit(
        target: Vector3(0, 1, 0),
        yaw: 0.8,
        pitch: 0.25,
        distance: 6,
      ),
    );

    expect(bridge.events, ['setCamera', 'setCamera']);
  });
}

final class _RecordingBridge implements RenderSceneBridge {
  final events = <String>[];

  @override
  Future<void> resetView() async {
    events.add('resetView');
  }

  @override
  Future<void> setCamera(StageCamera camera) async {
    events.add('setCamera');
  }

  @override
  Future<void> orbitCamera(double deltaYaw, double deltaPitch) async {
    events.add('orbitCamera');
  }

  @override
  Future<void> moveCamera(double deltaX, double deltaY) async {
    events.add('moveCamera');
  }

  @override
  Future<void> setEnvironment(RenderEnvironment environment) async {
    events.add('setEnvironment');
  }

  @override
  Future<void> loadModelAsset(RenderModelAsset asset) async {
    events.add('loadAsset:${asset.id.value}');
  }

  @override
  Future<void> createModelInstance(RenderModelInstance instance) async {
    events.add('createInstance:${instance.id.value}');
  }

  @override
  Future<void> setModelTransform(
    ModelInstanceId instanceId,
    PhysicsTransform transform,
  ) async {
    events.add('setTransform:${instanceId.value}');
  }

  @override
  Future<void> destroyModelInstance(ModelInstanceId instanceId) async {
    events.add('destroyInstance:${instanceId.value}');
  }

  @override
  Future<List<ModelAnimation>> getModelAnimations(
    ModelInstanceId instanceId,
  ) async {
    events.add('getAnimations:${instanceId.value}');
    return const [];
  }

  @override
  Future<void> playModelAnimation(
    ModelInstanceId instanceId,
    ModelAnimationPlayback playback,
  ) async {
    events.add('playAnimation:${instanceId.value}');
  }

  @override
  Future<void> pauseModelAnimation(ModelInstanceId instanceId) async {
    events.add('pauseAnimation:${instanceId.value}');
  }

  @override
  Future<void> resumeModelAnimation(ModelInstanceId instanceId) async {
    events.add('resumeAnimation:${instanceId.value}');
  }

  @override
  Future<void> stopModelAnimation(ModelInstanceId instanceId) async {
    events.add('stopAnimation:${instanceId.value}');
  }

  @override
  Future<void> createTexturedMesh(
    int meshId,
    TexturedMeshPrototype mesh,
  ) async {
    events.add('createMesh:$meshId');
  }

  @override
  Future<void> destroyTexturedMesh(int meshId) async {
    events.add('destroyMesh:$meshId');
  }

  @override
  Future<void> createLight(RenderLight light) async {
    events.add('createLight:${light.id.value}');
  }

  @override
  Future<void> setLightPosition(LightId lightId, Vector3 position) async {
    events.add('setLightPosition:${lightId.value}');
  }

  @override
  Future<void> setLightDirection(LightId lightId, Vector3 direction) async {
    events.add('setLightDirection:${lightId.value}');
  }

  @override
  Future<void> setLightIntensity(LightId lightId, double intensity) async {
    events.add('setLightIntensity:${lightId.value}');
  }

  @override
  Future<void> destroyLight(LightId lightId) async {
    events.add('destroyLight:${lightId.value}');
  }
}
