import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/virtual_joystick.dart';
import '../jolt_physics.dart' show PhysicsWorld, createPhysicsWorld;
import '../physics/collider_shape.dart' as physics;
import '../physics/physics_transform.dart';
import '../physics/rigid_body.dart';
import '../physics/vector3.dart';
import '../rendering/environment.dart';
import '../rendering/filament_viewport.dart';
import '../rendering/light.dart';
import '../rendering/model_asset.dart';
import '../rendering/render_environment_controller.dart';
import '../rendering/render_light_controller.dart';
import '../rendering/render_model_controller.dart';
import '../rendering/render_options.dart';
import '../rendering/render_options_controller.dart';
import '../rendering/stage_camera.dart';
import '../rendering/textured_mesh_prototype.dart';
import '../scene/camera_move_prototype.dart';
import '../scene/orbit_camera.dart';

enum _DemoScene {
  stage('1', 'Stage', 'Caravan model'),
  wind('2', 'Grass', 'Grass wind shader'),
  balls('3', 'Balls', 'Jolt sphere bodies'),
  showcase('4', 'All', 'Combined demo');

  const _DemoScene(this.keyLabel, this.label, this.status);

  final String keyLabel;
  final String label;
  final String status;

  bool get showsCaravan => this != balls;
  bool get showsFabric => this == showcase;
  bool get showsGrass => this == wind || this == showcase;
  bool get showsBalls => this == balls || this == showcase;
}

class FilamentFoxScenePage extends StatefulWidget {
  const FilamentFoxScenePage({super.key});

  @override
  State<FilamentFoxScenePage> createState() => _FilamentFoxScenePageState();
}

class _FilamentFoxScenePageState extends State<FilamentFoxScenePage>
    with SingleTickerProviderStateMixin {
  static const _initialCamera = StageCamera.orbit(
    target: Vector3(0, 1.2, 0),
    yaw: -0.62,
    pitch: 0.34,
    distance: 9.5,
  );

  static final _movementKeys = {
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };
  static const _ballRadius = 0.36;

  late final OrbitCamera _fallbackCamera;
  late final FilamentViewportController _viewportController;
  late final RenderEnvironmentController _environmentController;
  late final RenderOptionsController _optionsController;
  late final RenderLightController _lightController;
  late final RenderModelController _modelController;
  late final PhysicsWorld _physicsWorld;
  late final RenderModelAsset _caravanAsset;
  late final RenderModelAsset _poolBallAsset;
  late final FocusNode _keyboardFocusNode;
  late final Ticker _cameraTicker;

  final _cameraMove = const CameraMovePrototype(
    worldSpeed: 4.2,
    nativePanSpeed: 240,
  );
  static const _nativeVerticalPanSpeed = 240.0;
  final _pressedKeys = <LogicalKeyboardKey>{};
  final _ballBodies = <_BallBody>[];

  RenderModelInstance? _caravanInstance;
  RigidBody? _floorBody;
  var _scene = _DemoScene.stage;
  var _viewportRevision = 0;
  var _status = _DemoScene.stage.status;
  Duration? _lastCameraTick;

  @override
  void initState() {
    super.initState();
    _fallbackCamera = OrbitCamera()..setCamera(_initialCamera, notify: false);
    _viewportController = FilamentViewportController()
      ..setCamera(_initialCamera);
    _keyboardFocusNode = FocusNode()
      ..addListener(() {
        if (!_keyboardFocusNode.hasFocus) {
          _pressedKeys.clear();
        }
      });
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _cameraTicker = createTicker(_onCameraTick)..start();
    _environmentController = RenderEnvironmentController(
      initialEnvironment: const RenderEnvironment(
        skyColor: Vector3(0.44, 0.78, 0.9),
        ambientIntensity: 56000,
        reflectionIntensity: 0.9,
      ),
    );
    _optionsController = RenderOptionsController(
      initialOptions: const RenderOptions(
        shadows: true,
        shadowType: ShadowType.dpcf,
        ambientOcclusion: AmbientOcclusionOptions(
          enabled: true,
          radius: 0.45,
          intensity: 0.55,
          power: 1.0,
          quality: RenderQuality.low,
        ),
        msaa: MsaaOptions(enabled: true, sampleCount: 2),
      ),
    );
    _lightController = RenderLightController()
      ..createLight(
        const DirectionalLight(
          direction: Vector3(-0.35, -0.85, -0.25),
          intensity: 125000,
        ),
      )
      ..createLight(
        const PointLight(
          position: Vector3(0, 2.4, 2.2),
          color: Vector3(0.55, 0.75, 1),
          intensity: 2600,
          falloffRadius: 5,
          castShadows: false,
        ),
      );
    _modelController = RenderModelController();
    _physicsWorld = createPhysicsWorld();
    _caravanAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'assets/models/caravane_real.glb',
        verticalAnchor: ModelVerticalAnchor.bottom,
        normalizedScale: 2.7,
      ),
    );
    _poolBallAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'assets/models/pool_ball.glb',
        normalizedScale: _ballRadius * 2,
      ),
    );
    _activateScene(_DemoScene.stage, rebuild: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final scene = switch (key) {
        LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 =>
          _DemoScene.stage,
        LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 =>
          _DemoScene.wind,
        LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 =>
          _DemoScene.balls,
        LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 =>
          _DemoScene.showcase,
        _ => null,
      };
      if (scene != null) {
        _activateScene(scene);
        return;
      }
    }
    if (!_movementKeys.contains(key)) {
      return;
    }
    if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
      return;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressedKeys.add(key);
    }
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    _handleKeyEvent(event);
    return false;
  }

  void _onCameraTick(Duration elapsed) {
    final previousTick = _lastCameraTick;
    _lastCameraTick = elapsed;
    if (previousTick == null) {
      return;
    }

    final deltaSeconds =
        (elapsed - previousTick).inMicroseconds / Duration.microsecondsPerSecond;
    final horizontalInput = _keyboardMoveInput();
    final verticalInput = _keyboardVerticalInput();
    if (horizontalInput != JoystickValue.zero || verticalInput != 0) {
      _cameraMove.moveCamera(_fallbackCamera, horizontalInput, deltaSeconds);
      if (verticalInput != 0) {
        _fallbackCamera.moveTargetBy(
          right: 0,
          forward: 0,
          up: verticalInput * _cameraMove.worldSpeed * deltaSeconds,
        );
      }
      final nativeDelta = _cameraMove.nativeMove(horizontalInput, deltaSeconds);
      _viewportController.moveCamera(
        nativeDelta.right,
        -nativeDelta.forward,
        verticalInput * _nativeVerticalPanSpeed * deltaSeconds,
      );
    }

    if (_scene.showsBalls) {
      _stepBalls(deltaSeconds.clamp(0, 1 / 30).toDouble());
    }
  }

  JoystickValue _keyboardMoveInput() {
    var x = 0.0;
    var y = 0.0;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA)) {
      x -= 1;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD)) {
      x += 1;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyW)) {
      y -= 1;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS)) {
      y += 1;
    }

    final length = math.sqrt(x * x + y * y);
    if (length == 0) {
      return JoystickValue.zero;
    }
    if (length > 1) {
      x /= length;
      y /= length;
    }
    return JoystickValue(x, y);
  }

  double _keyboardVerticalInput() {
    var y = 0.0;
    if (_pressedKeys.contains(LogicalKeyboardKey.space)) {
      y += 1;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.shiftRight)) {
      y -= 1;
    }
    return y;
  }

  Future<void> _onRendererReady() async {
    final caravanInstance = _caravanInstance;
    if (caravanInstance == null) {
      setState(() => _status = _scene.status);
      return;
    }
    final animations = await _modelController.getAnimations(caravanInstance);
    if (!mounted) {
      return;
    }
    if (animations.isNotEmpty) {
      _modelController.playAnimation(
        caravanInstance,
        animationIndex: animations.first.index,
      );
    }
    setState(() {
      _status = animations.isEmpty
          ? _scene.status
          : '${_scene.status}, ${animations.length} animations';
    });
  }

  void _activateScene(_DemoScene scene, {bool rebuild = true}) {
    _clearSceneObjects();
    _scene = scene;
    _status = scene.status;
    if (scene.showsCaravan) {
      _caravanInstance = _modelController.createInstance(
        _caravanAsset,
        transform: const PhysicsTransform(position: Vector3.zero),
      );
    }
    if (scene.showsBalls) {
      _createBallScene();
    }
    _viewportRevision++;
    if (rebuild && mounted) {
      setState(() {});
      _keyboardFocusNode.requestFocus();
    }
  }

  void _clearSceneObjects() {
    final caravanInstance = _caravanInstance;
    if (caravanInstance != null) {
      _modelController.destroyInstance(caravanInstance);
      _caravanInstance = null;
    }
    for (final ball in _ballBodies) {
      _modelController.destroyInstance(ball.instance);
      _physicsWorld.destroyBody(ball.body);
    }
    _ballBodies.clear();
    final floorBody = _floorBody;
    if (floorBody != null) {
      _physicsWorld.destroyBody(floorBody);
      _floorBody = null;
    }
  }

  void _createBallScene() {
    _floorBody = _physicsWorld.createBody(
      const RigidBodySettings(
        shape: physics.BoxShape(halfWidth: 4, halfHeight: 0.1, halfDepth: 3),
        motionType: MotionType.static,
        transform: PhysicsTransform(position: Vector3(0, -0.1, 0)),
        friction: 0.85,
        restitution: 0.25,
      ),
    );

    for (var index = 0; index < 2; index++) {
      final position = _ballSpawnPosition(index);
      final transform = PhysicsTransform(position: position);
      final body = _physicsWorld.createBody(
        RigidBodySettings(
          shape: const physics.SphereShape(radius: _ballRadius),
          motionType: MotionType.dynamic,
          transform: transform,
          linearVelocity: Vector3(
            0,
            0,
            0,
          ),
          angularVelocity: index == 0
              ? Vector3.zero
              : const Vector3(0.8, 0.4, 0.2),
          friction: 0.45,
          restitution: 0.72,
        ),
      );
      final instance = _modelController.createInstance(
        _poolBallAsset,
        transform: transform,
      );
      _ballBodies.add(_BallBody(body: body, instance: instance));
    }
  }

  Vector3 _ballSpawnPosition(int index) =>
      index == 0 ? const Vector3(0, _ballRadius, 0) : const Vector3(0, 21.6, 0);

  void _stepBalls(double deltaSeconds) {
    _physicsWorld.step(deltaSeconds);
    for (var index = 0; index < _ballBodies.length; index++) {
      final ball = _ballBodies[index];
      final transform = _physicsWorld.getTransform(ball.body);
      if (transform.position.y < -6) {
        _resetBall(index, ball);
        continue;
      }
      _modelController.setTransform(ball.instance, transform);
    }
  }

  void _resetBall(int index, _BallBody ball) {
    final transform = PhysicsTransform(
      position: _ballSpawnPosition(index),
    );
    _physicsWorld
      ..setTransform(ball.body, transform)
      ..setLinearVelocity(ball.body, Vector3.zero)
      ..setAngularVelocity(ball.body, Vector3(0.8, 0.4, 0.2));
    _modelController.setTransform(ball.instance, transform);
  }

  List<TexturedMeshPrototype> _meshPrototypesForScene() {
    return [
      _scene.showsFabric ? _createWindFabricMesh() : _createHiddenMesh(),
      _scene.showsGrass ? _createWindGrassMesh() : _createHiddenMesh(),
      _createHiddenMesh(),
    ];
  }

  @override
  void dispose() {
    _clearSceneObjects();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _cameraTicker.dispose();
    _keyboardFocusNode.dispose();
    _viewportController.detach();
    _environmentController.detach();
    _optionsController.detach();
    _lightController.detach();
    _modelController.detach();
    _physicsWorld.dispose();
    _fallbackCamera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (_) {},
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _keyboardFocusNode.requestFocus(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FilamentViewport(
                key: ValueKey('demo-${_scene.name}-$_viewportRevision'),
                cube: const PhysicsTransform(position: Vector3.zero),
                fallbackCamera: _fallbackCamera,
                controller: _viewportController,
                environmentController: _environmentController,
                optionsController: _optionsController,
                lightController: _lightController,
                modelController: _modelController,
                meshPrototypes: _meshPrototypesForScene(),
                showFallbackPreview: false,
                onRendererReady: _onRendererReady,
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xcc05070a),
                        border: Border.all(color: const Color(0x5538bdf8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Text(
                          _status,
                          style: const TextStyle(
                            color: Color(0xffdbeafe),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _SceneSwitcher(
                      selected: _scene,
                      onSelect: _activateScene,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _BallBody {
  const _BallBody({required this.body, required this.instance});

  final RigidBody body;
  final RenderModelInstance instance;
}

class _SceneSwitcher extends StatelessWidget {
  const _SceneSwitcher({required this.selected, required this.onSelect});

  final _DemoScene selected;
  final ValueChanged<_DemoScene> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xcc05070a),
        border: Border.all(color: const Color(0x5538bdf8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final scene in _DemoScene.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Focus(
                  canRequestFocus: false,
                  descendantsAreFocusable: false,
                  child: TextButton(
                    onPressed: () => onSelect(scene),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(54, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      backgroundColor: scene == selected
                          ? const Color(0xff2563eb)
                          : const Color(0x220f172a),
                      foregroundColor: const Color(0xffdbeafe),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text('${scene.keyLabel} ${scene.label}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

TexturedMeshPrototype _createHiddenMesh() {
  const texture = MeshTexturePrototype(
    primaryColor: Color(0x00000000),
    secondaryColor: Color(0x00000000),
  );
  return TexturedMeshPrototype(
    vertices: const [
      MeshVertex(position: Vector3(-0.01, -1000, -0.01), uv: Offset.zero),
      MeshVertex(position: Vector3(0.01, -1000, -0.01), uv: Offset(1, 0)),
      MeshVertex(position: Vector3(0.01, -1000, 0.01), uv: Offset(1, 1)),
      MeshVertex(position: Vector3(-0.01, -1000, 0.01), uv: Offset(0, 1)),
    ],
    indices: const [0, 1, 2, 0, 2, 3],
    material: MeshMaterialPrototype.checker(texture),
  );
}

TexturedMeshPrototype _createWindFabricMesh() {
  const width = 1.6;
  const height = 1.15;
  const columns = 24;
  const rows = 16;
  const originX = 2.25;
  const originY = 0.24;
  const originZ = -1.25;
  const texture = MeshTexturePrototype.asset(
    assetPath: 'textures/fabric/Fabric018_2K-Color.png',
    repeatU: 2.0,
    repeatV: 1.4,
  );
  final material = MeshMaterialPrototype.filamat(
    assetPath: 'materials/grass_wind.filamat',
    texture: texture,
    roughnessFactor: 0.92,
    doubleSided: true,
    uniforms: [
      MaterialShaderUniform.float('windStrength', 0.16),
      MaterialShaderUniform.float('windScale', 4.2),
      MaterialShaderUniform.float('reflectance', 0.35),
    ],
  );
  final vertices = <MeshVertex>[];
  for (var row = 0; row <= rows; row++) {
    final v = row / rows;
    for (var column = 0; column <= columns; column++) {
      final u = column / columns;
      final sag = math.sin(u * math.pi) * v * 0.08;
      vertices.add(
        MeshVertex(
          position: Vector3(
            originX + (u - 0.5) * width,
            originY + v * height - sag,
            originZ,
          ),
          normal: const Vector3(0, 0, -1),
          uv: Offset(u * texture.repeatU, v * texture.repeatV),
        ),
      );
    }
  }

  final indices = <int>[];
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      final topLeft = row * (columns + 1) + column;
      final topRight = topLeft + 1;
      final bottomLeft = topLeft + columns + 1;
      final bottomRight = bottomLeft + 1;
      indices.addAll([
        topLeft,
        bottomLeft,
        topRight,
        topRight,
        bottomLeft,
        bottomRight,
      ]);
    }
  }

  return TexturedMeshPrototype(
    vertices: vertices,
    indices: indices,
    material: material,
  );
}

TexturedMeshPrototype _createWindGrassMesh() {
  const originX = 4.35;
  const originY = 0.05;
  const originZ = -1.25;
  const cardWidth = 0.9;
  const cardHeight = 1.1;
  const texture = MeshTexturePrototype.asset(
    assetPath: 'textures/grass/travushka_0.png',
  );
  final material = MeshMaterialPrototype.filamat(
    assetPath: 'materials/grass_card_wind.filamat',
    texture: texture,
    baseColor: Colors.white,
    roughnessFactor: 0.88,
    doubleSided: true,
    uniforms: [
      MaterialShaderUniform.float('windStrength', 0.18),
      MaterialShaderUniform.float('windScale', 5.2),
      MaterialShaderUniform.float('anchorY', originY),
      MaterialShaderUniform.float('windHeight', cardHeight),
      MaterialShaderUniform.float('reflectance', 0.25),
    ],
  );
  final vertices = <MeshVertex>[];
  final indices = <int>[];
  void addCard({
    required double centerX,
    required double centerZ,
    required double dirX,
    required double dirZ,
  }) {
    final baseIndex = vertices.length;
    final halfX = dirX * cardWidth * 0.5;
    final halfZ = dirZ * cardWidth * 0.5;
    final normal = Vector3(-dirZ, 0, dirX);
    vertices.addAll([
      MeshVertex(
        position: Vector3(centerX - halfX, originY, centerZ - halfZ),
        normal: normal,
        uv: const Offset(0, 1),
      ),
      MeshVertex(
        position: Vector3(centerX + halfX, originY, centerZ + halfZ),
        normal: normal,
        uv: const Offset(1, 1),
      ),
      MeshVertex(
        position: Vector3(
          centerX + halfX,
          originY + cardHeight,
          centerZ + halfZ,
        ),
        normal: normal,
        uv: const Offset(1, 0),
      ),
      MeshVertex(
        position: Vector3(
          centerX - halfX,
          originY + cardHeight,
          centerZ - halfZ,
        ),
        normal: normal,
        uv: const Offset(0, 0),
      ),
    ]);
    indices.addAll([
      baseIndex,
      baseIndex + 1,
      baseIndex + 2,
      baseIndex,
      baseIndex + 2,
      baseIndex + 3,
    ]);
  }

  addCard(centerX: originX, centerZ: originZ, dirX: 1, dirZ: 0);
  addCard(centerX: originX, centerZ: originZ, dirX: 0, dirZ: 1);
  addCard(centerX: originX - 0.28, centerZ: originZ + 0.25, dirX: 0.7, dirZ: 0.7);
  addCard(centerX: originX + 0.24, centerZ: originZ - 0.2, dirX: 0.7, dirZ: -0.7);

  return TexturedMeshPrototype(
    vertices: vertices,
    indices: indices,
    material: material,
  );
}
