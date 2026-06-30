import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/stage_3d.dart';

void main() {
  test('StageObject owns a transform component by default', () {
    final object = StageObject('fox');

    expect(object.transform.position, Vector3.zero);
    expect(object.get<TransformComponent>(), same(object.transform));
    expect(object.components, contains(object.transform));
  });

  test('StageObject.node attaches initial components', () {
    final component = _CountingComponent();

    final object = StageObject.node(
      'fox',
      transform: const PhysicsTransform(position: Vector3(1, 2, 3)),
      components: [component],
    );

    expect(object.transform.position.x, 1);
    expect(object.transform.position.y, 2);
    expect(object.transform.position.z, 3);
    expect(object.components, contains(component));
    expect(component.attached, 1);
  });

  test('StageScene updates attached components', () {
    final scene = StageScene();
    final component = _CountingComponent();

    scene.add(StageObject('fox')..add(component));
    scene.update(0.5);
    scene.update(0.25);

    expect(component.attached, 1);
    expect(component.updates, 2);
    expect(component.elapsed, 0.75);
  });

  test('StageScene can find and remove objects', () {
    final scene = StageScene();
    final component = _CountingComponent();
    final fox = scene.add(StageObject('fox')..add(component));

    expect(scene.findByName('fox'), same(fox));
    expect(scene.remove(fox), isTrue);
    expect(scene.findByName('fox'), isNull);
    expect(component.detached, 1);
  });

  test('TransformComponent can translate an object', () {
    final transform = TransformComponent(
      transform: const PhysicsTransform(position: Vector3(1, 2, 3)),
    );

    transform.translate(2, -1, 0.5);

    expect(transform.position.x, 3);
    expect(transform.position.y, 1);
    expect(transform.position.z, 3.5);
  });

  test('PhysicsBodyComponent writes body transform back to the object', () {
    final world = createPhysicsWorld();
    addTearDown(world.dispose);
    final object = StageObject('body');
    final body = object.add(
      PhysicsBodyComponent(
        world,
        settings: const RigidBodySettings(
          shape: SphereShape(radius: 0.5),
          motionType: MotionType.dynamic,
          transform: PhysicsTransform(position: Vector3(0, 2, 0)),
        ),
      ),
    );

    world.setTransform(
      body.body!,
      const PhysicsTransform(position: Vector3(1, 3, 2)),
    );
    object.update(0.016);

    expect(object.transform.position.x, 1);
    expect(object.transform.position.y, 3);
    expect(object.transform.position.z, 2);
  });

  test('RenderModelComponent mirrors object transform to renderer', () {
    final bridge = _StageRecordingBridge();
    final models = RenderModelController()..attachBridge(bridge);
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/tree.glb'),
    );
    final object = StageObject(
      'tree',
      transform: TransformComponent(
        transform: const PhysicsTransform(position: Vector3(1, 0, 2)),
      ),
    );

    object.add(RenderModelComponent(controller: models, asset: asset));
    object.transform.translate(2, 0, 1);
    object.update(0.016);

    expect(bridge.events, [
      'loadAsset:1',
      'createInstance:1',
      'setTransform:1',
    ]);
  });

  test('RenderModelComponent applies visual offset to renderer transform', () {
    final bridge = _StageRecordingBridge();
    final models = RenderModelController()..attachBridge(bridge);
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/character.glb'),
    );
    final object = StageObject(
      'character',
      transform: TransformComponent(
        transform: const PhysicsTransform(position: Vector3(1, 2, 3)),
      ),
    );

    object.add(
      RenderModelComponent(
        controller: models,
        asset: asset,
        visualOffset: const Vector3(0, 0.35, 0),
      ),
    );
    object.update(0.016);

    expect(bridge.lastTransform?.position.x, 1);
    expect(bridge.lastTransform?.position.y, 2.35);
    expect(bridge.lastTransform?.position.z, 3);
  });

  test('PositionedModel creates a render component with local offset', () {
    final bridge = _StageRecordingBridge();
    final models = RenderModelController()..attachBridge(bridge);
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/hat.glb'),
    );
    final object = StageObject.node(
      'character',
      transform: const PhysicsTransform(position: Vector3(1, 2, 3)),
      components: [
        PositionedModel(
          asset: asset,
          position: const Vector3(0, 1, 0),
        ).toComponent(models),
      ],
    );

    object.update(0.016);

    expect(bridge.lastTransform?.position.x, 1);
    expect(bridge.lastTransform?.position.y, 3);
    expect(bridge.lastTransform?.position.z, 3);
  });
}

final class _CountingComponent extends StageComponent {
  var attached = 0;
  var detached = 0;
  var updates = 0;
  var elapsed = 0.0;

  @override
  void onAttach(StageObject object) {
    attached++;
  }

  @override
  void update(double deltaSeconds) {
    updates++;
    elapsed += deltaSeconds;
  }

  @override
  void onDetach() {
    detached++;
  }
}

final class _StageRecordingBridge implements RenderSceneBridge {
  final events = <String>[];
  PhysicsTransform? lastTransform;

  @override
  Future<void> resetView() async {}

  @override
  Future<void> setCamera(StageCamera camera) async {}

  @override
  Future<void> orbitCamera(double deltaYaw, double deltaPitch) async {}

  @override
  Future<void> moveCamera(double deltaX, double deltaY) async {}

  @override
  Future<void> setEnvironment(RenderEnvironment environment) async {}

  @override
  Future<void> setRenderOptions(RenderOptions options) async {}

  @override
  Future<void> loadModelAsset(RenderModelAsset asset) async {
    events.add('loadAsset:${asset.id.value}');
  }

  @override
  Future<void> unloadModelAsset(ModelAssetId assetId) async {}

  @override
  Future<void> createModelInstance(RenderModelInstance instance) async {
    events.add('createInstance:${instance.id.value}');
  }

  @override
  Future<void> setModelTransform(
    ModelInstanceId instanceId,
    PhysicsTransform transform,
  ) async {
    lastTransform = transform;
    events.add('setTransform:${instanceId.value}');
  }

  @override
  Future<void> destroyModelInstance(ModelInstanceId instanceId) async {}

  @override
  Future<List<ModelAnimation>> getModelAnimations(
    ModelInstanceId instanceId,
  ) async => const [];

  @override
  Future<void> playModelAnimation(
    ModelInstanceId instanceId,
    ModelAnimationPlayback playback,
  ) async {}

  @override
  Future<void> pauseModelAnimation(ModelInstanceId instanceId) async {}

  @override
  Future<void> resumeModelAnimation(ModelInstanceId instanceId) async {}

  @override
  Future<void> stopModelAnimation(ModelInstanceId instanceId) async {}

  @override
  Future<void> createTexturedMesh(
    int meshId,
    TexturedMeshPrototype mesh,
  ) async {}

  @override
  Future<void> destroyTexturedMesh(int meshId) async {}

  @override
  Future<void> createLight(RenderLight light) async {}

  @override
  Future<void> setLightPosition(LightId lightId, Vector3 position) async {}

  @override
  Future<void> setLightDirection(LightId lightId, Vector3 direction) async {}

  @override
  Future<void> setLightIntensity(LightId lightId, double intensity) async {}

  @override
  Future<void> destroyLight(LightId lightId) async {}
}
