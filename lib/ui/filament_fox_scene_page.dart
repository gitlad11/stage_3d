import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/virtual_joystick.dart';
import '../jolt_physics.dart' show PhysicsWorld, createPhysicsWorld;
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
import '../scene/camera_move_prototype.dart';
import '../scene/orbit_camera.dart';

class FilamentFoxScenePage extends StatefulWidget {
  const FilamentFoxScenePage({super.key});

  @override
  State<FilamentFoxScenePage> createState() => _FilamentFoxScenePageState();
}

class _FilamentFoxScenePageState extends State<FilamentFoxScenePage>
    with SingleTickerProviderStateMixin {
  static const _initialCamera = StageCamera.orbit(
    target: Vector3(0, 1.5, 0),
    yaw: 0.5,
    pitch: 0.25,
    distance: 10,
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

  late final OrbitCamera _fallbackCamera;
  late final FilamentViewportController _viewportController;
  late final RenderEnvironmentController _environmentController;
  late final RenderOptionsController _optionsController;
  late final RenderLightController _lightController;
  late final RenderModelController _modelController;
  late final PhysicsWorld _physicsWorld;
  RenderModelAsset? _houseAsset;
  RenderModelInstance? _houseInstance;
  late final FocusNode _keyboardFocusNode;
  late final Ticker _cameraTicker;
  late final VirtualJoystickController _moveJoystick;
  late final VirtualJoystickController _orbitJoystick;

  final _cameraMove = const CameraMovePrototype(
    worldSpeed: 2.1,
    nativePanSpeed: 240,
  );
  static const _nativeOrbitSpeed = 1.8;
  final _pressedKeys = <LogicalKeyboardKey>{};

  var _status = 'House';
  Duration? _lastCameraTick;
  RigidBody? _floorBody;
  StageCamera _lastSyncedCamera = _initialCamera;

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
    _moveJoystick = VirtualJoystickController();
    _orbitJoystick = VirtualJoystickController();
    _environmentController = RenderEnvironmentController(
      initialEnvironment: const RenderEnvironment(
        skyColor: Vector3(0.54, 0.72, 0.95),
        ambientIntensity: 48000,
        reflectionIntensity: 0.85,
      ),
    );
    _optionsController = RenderOptionsController(
      initialOptions: const RenderOptions(
        shadows: true,
        shadowType: ShadowType.pcf,
        ambientOcclusion: AmbientOcclusionOptions(
          enabled: true,
          radius: 0.5,
          intensity: 0.6,
          power: 1.0,
          quality: RenderQuality.low,
        ),
        msaa: MsaaOptions(enabled: true, sampleCount: 4),
      ),
    );
    _lightController = RenderLightController()
      ..createLight(
        const DirectionalLight(
          direction: Vector3(-0.45, -0.8, -0.35),
          intensity: 130000,
        ),
      )
      ..createLight(
        const PointLight(
          position: Vector3(2, 1.8, 2.5),
          color: Vector3(1, 0.92, 0.8),
          intensity: 1800,
          falloffRadius: 6,
          castShadows: false,
        ),
      );
    _modelController = RenderModelController();
    _physicsWorld = createPhysicsWorld();
    _loadHouseScene();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
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
    final horizontalInput = _combinedMoveInput();
    final verticalInput = _keyboardVerticalInput();

    // Fly movement: forward/back follows camera view direction (including pitch).
    if (horizontalInput != JoystickValue.zero || verticalInput != 0) {
      _fallbackCamera.moveInViewDirection(
        right: -horizontalInput.x * _cameraMove.worldSpeed * deltaSeconds,
        forward: horizontalInput.y * _cameraMove.worldSpeed * deltaSeconds,
        up: verticalInput * _cameraMove.worldSpeed * deltaSeconds,
      );
    }

    final orbitInput = _orbitJoystick.value;
    if (orbitInput != JoystickValue.zero) {
      final deltaYaw = -orbitInput.x * _nativeOrbitSpeed * deltaSeconds;
      final deltaPitch = orbitInput.y * _nativeOrbitSpeed * deltaSeconds;
      _fallbackCamera.orbitBy(deltaYaw, deltaPitch);
    }

    // Sync the full orbit camera state to the native renderer (only when changed).
    final camera = StageCamera.orbit(
      target: _fallbackCamera.target,
      yaw: _fallbackCamera.yaw,
      pitch: _fallbackCamera.pitch,
      distance: _fallbackCamera.distance,
    );
    if (camera != _lastSyncedCamera) {
      _lastSyncedCamera = camera;
      _viewportController.setCamera(camera);
    }

    if (mounted) {
      _viewportController.requestRender();
    }
  }

  JoystickValue _combinedMoveInput() {
    final keyboard = _keyboardMoveInput();
    final joystick = _moveJoystick.value;
    final x = (keyboard.x + joystick.x).clamp(-1.0, 1.0).toDouble();
    final y = (keyboard.y + joystick.y).clamp(-1.0, 1.0).toDouble();
    if (x == 0 && y == 0) {
      return JoystickValue.zero;
    }
    return JoystickValue(x, y);
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
    final houseInstance = _houseInstance;
    if (houseInstance == null || !mounted) {
      return;
    }
    final animations = await _modelController.getAnimations(houseInstance);
    if (!mounted) {
      return;
    }
    if (animations.isNotEmpty) {
      _modelController.playAnimation(
        houseInstance,
        animationIndex: animations.first.index,
      );
    }
    setState(() {
      _status = animations.isEmpty
          ? 'House'
          : 'House, ${animations.length} animations';
    });
  }

  void _loadHouseScene() {
    _clearHouseScene();
    final houseAsset = _houseAsset ??= _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'assets/models/appartement.glb',
        verticalAnchor: ModelVerticalAnchor.bottom,
        normalizedScale: 1.0,
        castShadows: true,
        receiveShadows: true,
      ),
    );
    _houseInstance = _modelController.createInstance(
      houseAsset,
      transform: const PhysicsTransform(position: Vector3(0, 0, 0)),
    );
    _fallbackCamera.setCamera(_initialCamera, notify: false);
    _viewportController.setCamera(_initialCamera);
    _lastSyncedCamera = _initialCamera;
    _moveJoystick.reset();
    _orbitJoystick.reset();
    _pressedKeys.clear();
    setState(() => _status = 'House');
  }

  void _clearHouseScene() {
    final houseInstance = _houseInstance;
    if (houseInstance != null) {
      _modelController.destroyInstance(houseInstance);
      _houseInstance = null;
    }
    final floorBody = _floorBody;
    if (floorBody != null) {
      _physicsWorld.destroyBody(floorBody);
      _floorBody = null;
    }
  }

  @override
  void dispose() {
    _clearHouseScene();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _cameraTicker.dispose();
    _moveJoystick.dispose();
    _orbitJoystick.dispose();
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
                key: const ValueKey('demo-filament-view'),
                cube: const PhysicsTransform(position: Vector3.zero),
                fallbackCamera: _fallbackCamera,
                controller: _viewportController,
                environmentController: _environmentController,
                optionsController: _optionsController,
                lightController: _lightController,
                modelController: _modelController,
                meshPrototypes: const [],
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
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: VirtualJoystick(
                      key: const ValueKey('stage-move-joystick'),
                      controller: _moveJoystick,
                      size: 112,
                      accentColor: const Color(0xff7dd3fc),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: VirtualJoystick(
                      key: const ValueKey('stage-orbit-joystick'),
                      controller: _orbitJoystick,
                      size: 112,
                      accentColor: const Color(0xffc4b5fd),
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
