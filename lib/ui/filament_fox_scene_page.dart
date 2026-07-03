import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/virtual_joystick.dart';
import '../physics/physics_transform.dart';
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
    target: Vector3(0, 0.75, 0),
    yaw: -0.62,
    pitch: 0.24,
    distance: 4.8,
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
  late final RenderModelInstance _caravanInstance;
  late final FocusNode _keyboardFocusNode;
  late final Ticker _cameraTicker;

  final _cameraMove = const CameraMovePrototype(
    worldSpeed: 4.2,
    nativePanSpeed: 240,
  );
  static const _nativeVerticalPanSpeed = 240.0;
  final _pressedKeys = <LogicalKeyboardKey>{};

  var _status = 'Loading caravane_real.glb';
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
    final caravanAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'assets/models/caravane_real.glb',
        verticalAnchor: ModelVerticalAnchor.bottom,
        normalizedScale: 2.7,
      ),
    );
    _caravanInstance = _modelController.createInstance(
      caravanAsset,
      transform: const PhysicsTransform(position: Vector3.zero),
    );
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

  void _onCameraTick(Duration elapsed) {
    final previousTick = _lastCameraTick;
    _lastCameraTick = elapsed;
    if (previousTick == null) {
      return;
    }

    final horizontalInput = _keyboardMoveInput();
    final verticalInput = _keyboardVerticalInput();
    if (horizontalInput == JoystickValue.zero && verticalInput == 0) {
      return;
    }

    final deltaSeconds =
        (elapsed - previousTick).inMicroseconds / Duration.microsecondsPerSecond;
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
    final animations = await _modelController.getAnimations(_caravanInstance);
    if (!mounted) {
      return;
    }
    if (animations.isNotEmpty) {
      _modelController.playAnimation(
        _caravanInstance,
        animationIndex: animations.first.index,
      );
    }
    setState(() {
      _status = animations.isEmpty
          ? 'Caravan model loaded'
          : 'Caravan model loaded, ${animations.length} animations';
    });
  }

  @override
  void dispose() {
    _cameraTicker.dispose();
    _keyboardFocusNode.dispose();
    _viewportController.detach();
    _environmentController.detach();
    _optionsController.detach();
    _lightController.detach();
    _modelController.detach();
    _fallbackCamera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            FilamentViewport(
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
          ],
        ),
      ),
    );
  }
}
