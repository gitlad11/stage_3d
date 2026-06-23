import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter/scheduler.dart';
import 'package:stage_3d/jolt_physics.dart';
import 'package:stage_3d/jolt_rendering.dart';

const _wideCamera = StageCamera.orbit(
  target: Vector3(0, 0.5, 0),
  yaw: -0.55,
  pitch: 0.32,
  distance: 7,
);

const _closeCamera = StageCamera.orbit(
  target: Vector3(0, 1.1, 0),
  yaw: 0.15,
  pitch: 0.18,
  distance: 3,
);

void main() {
  runApp(const Stage3DExampleApp());
}

class Stage3DExampleApp extends StatelessWidget {
  const Stage3DExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stage 3D Example',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff38bdf8),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff08111f),
      ),
      home: const Stage3DExampleScene(),
    );
  }
}

class Stage3DExampleScene extends StatefulWidget {
  const Stage3DExampleScene({super.key});

  @override
  State<Stage3DExampleScene> createState() => _Stage3DExampleSceneState();
}

class _Stage3DExampleSceneState extends State<Stage3DExampleScene>
    with SingleTickerProviderStateMixin {
  late final PhysicsWorld _world;
  late final StageScene _scene;
  late final OrbitCamera _camera;
  late final Ticker _ticker;
  late final FilamentViewportController _viewportController;
  late final RenderEnvironmentController _environmentController;
  late final RenderLightController _lightController;
  late final RenderModelController _modelController;
  late final RenderLight _followLight;
  late final PhysicsBodyComponent _foxBody;
  late final RenderModelComponent _foxModel;
  late final List<TexturedMeshPrototype> _meshes;
  var _status = 'Loading renderer';
  var _activeCamera = _wideCamera;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();

    _world = createPhysicsWorld();
    _scene = StageScene();
    _camera = OrbitCamera();
    _viewportController = FilamentViewportController();
    _viewportController.setCamera(_wideCamera);
    _environmentController = RenderEnvironmentController(
      initialEnvironment: const RenderEnvironment(
        skyColor: Vector3(0.34, 0.62, 0.84),
        ambientIntensity: 42000,
        reflectionIntensity: 0.85,
      ),
    );
    _lightController = RenderLightController()
      ..createLight(
        const DirectionalLight(
          direction: Vector3(-0.25, -0.75, -0.45),
          intensity: 110000,
        ),
      );
    _followLight = _lightController.createLight(
      const PointLight(
        position: Vector3(0, 2.5, 1.5),
        color: Vector3(0.45, 0.72, 1),
        intensity: 2800,
        falloffRadius: 5,
        castShadows: false,
      ),
    );
    _modelController = RenderModelController();
    _meshes = [_createGroundMesh()];

    final floorBody = PhysicsBodyComponent(
      _world,
      settings: const RigidBodySettings(
        shape: BoxShape(halfWidth: 5, halfHeight: 0.1, halfDepth: 5),
        motionType: MotionType.static,
        transform: PhysicsTransform(position: Vector3(0, -0.1, 0)),
      ),
    );
    _scene.add(StageObject.node('floor', components: [floorBody]));

    final foxAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'models/Fox.glb',
        verticalAnchor: ModelVerticalAnchor.bottom,
      ),
    );
    _foxBody = PhysicsBodyComponent(
      _world,
      settings: const RigidBodySettings(
        shape: CompoundShape([
          PositionedShape(
            shape: CapsuleShape(halfHeight: 0.65, radius: 0.35),
            position: Vector3(0, 0.65, 0),
          ),
          PositionedShape(
            shape: BoxShape(halfWidth: 0.4, halfHeight: 0.2, halfDepth: 0.3),
            position: Vector3(0, 0.15, 0),
          ),
        ]),
        motionType: MotionType.dynamic,
        transform: PhysicsTransform(position: Vector3(0, 3.2, 0)),
        linearVelocity: Vector3(0.35, 0, 0),
      ),
    );
    _foxModel = RenderModelComponent(
      controller: _modelController,
      asset: foxAsset,
      visualOffset: const Vector3(0, 0.15, 0),
    );
    _scene.add(StageObject.node('fox', components: [_foxBody, _foxModel]));
    _foxBody.addImpulse(const Vector3(0.8, 0, 0.2));

    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _startFirstAnimation() async {
    final animations = await _modelController.getAnimations(
      _foxModel.requireInstance,
    );
    if (!mounted) {
      return;
    }
    if (animations.isEmpty) {
      setState(() => _status = _world.engineLabel);
      return;
    }
    _modelController.playAnimation(
      _foxModel.requireInstance,
      animationIndex: animations.first.index,
    );
    setState(() => _status = '${animations.first.name} animation');
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) {
      return;
    }

    final deltaSeconds =
        (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond;
    _world.step(deltaSeconds);
    _scene.update(deltaSeconds);

    final foxPosition = _foxBody.transform.position;
    _lightController.setPosition(
      _followLight,
      foxPosition.translate(0, 1.8, 1.2),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scene.dispose();
    _camera.dispose();
    _world.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FilamentViewport(
              cube: _foxBody.transform,
              fallbackCamera: _camera,
              controller: _viewportController,
              environmentController: _environmentController,
              lightController: _lightController,
              modelController: _modelController,
              meshPrototypes: _meshes,
              onRendererReady: _startFirstAnimation,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xd908111f),
                      border: Border.all(color: const Color(0x6638bdf8)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        _status,
                        style: const TextStyle(
                          color: Color(0xffe0f2fe),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<StageCamera>(
                    segments: const [
                      ButtonSegment(value: _wideCamera, label: Text('Wide')),
                      ButtonSegment(value: _closeCamera, label: Text('Close')),
                    ],
                    selected: {_activeCamera},
                    onSelectionChanged: (selection) {
                      setState(() => _activeCamera = selection.single);
                      _viewportController.setCamera(_activeCamera);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TexturedMeshPrototype _createGroundMesh() {
  const texture = MeshTexturePrototype(
    primaryColor: Color(0xff164e63),
    secondaryColor: Color(0xff22d3ee),
    repeatU: 8,
    repeatV: 8,
  );
  return TexturedMeshPrototype.plane(
    width: 10,
    depth: 10,
    texture: texture,
    material: MeshMaterialPrototype.checker(texture, roughnessFactor: 0.92),
    collider: const MeshColliderPrototype.staticBox(
      BoxShape(halfWidth: 5, halfHeight: 0.1, halfDepth: 5),
    ),
  );
}
