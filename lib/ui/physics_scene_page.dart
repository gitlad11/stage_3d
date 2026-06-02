import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../jolt_physics.dart';
import '../rendering/filament_viewport.dart';
import '../rendering/light.dart';
import '../rendering/model_asset.dart';
import '../rendering/physics_debug_overlay.dart';
import '../rendering/render_light_controller.dart';
import '../rendering/render_model_controller.dart';
import '../scene/orbit_camera.dart';
import '../scene/physics_scene.dart';

class PhysicsScenePage extends StatefulWidget {
  const PhysicsScenePage({super.key});

  @override
  State<PhysicsScenePage> createState() => _PhysicsScenePageState();
}

class _PhysicsScenePageState extends State<PhysicsScenePage>
    with SingleTickerProviderStateMixin {
  late final PhysicsScene _scene;
  late final OrbitCamera _camera;
  late final Ticker _ticker;
  late final FilamentViewportController _viewportController;
  late final RenderLightController _lightController;
  late final RenderLight _modelLight;
  late final RenderModelController _modelController;
  late final RenderModelInstance _foxModel;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _scene = PhysicsScene()..addListener(_refresh);
    _camera = OrbitCamera()..addListener(_refresh);
    _viewportController = FilamentViewportController();
    _lightController = RenderLightController()
      ..createLight(
        const DirectionalLight(
          direction: Vector3(0, -0.5, -1),
          intensity: 120000,
        ),
      );
    _modelLight = _lightController.createLight(
      const PointLight(
        position: Vector3(0, 3, 0),
        color: Vector3(0.45, 0.7, 1),
        intensity: 3500,
        falloffRadius: 5,
        castShadows: false,
      ),
    );
    _modelController = RenderModelController();
    final foxAsset = _modelController.loadAsset(
      const ModelAsset(assetPath: 'models/Fox.glb', animationIndex: 0),
    );
    _foxModel = _modelController.createInstance(
      foxAsset,
      transform: _scene.model.transform,
    );
    _ticker = createTicker(_onTick)..start();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) {
      return;
    }
    _scene.step(
      (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond,
    );
    final position = _scene.model.transform.position;
    _lightController.setPosition(_modelLight, position.translate(0, 1.5, 0.5));
    _modelController.setTransform(_foxModel, _scene.model.transform);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _camera
      ..removeListener(_refresh)
      ..dispose();
    _scene
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cube = _scene.model.transform;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerUp: (_) => _scene.castRayAtModel(),
              child: FilamentViewport(
                cube: cube,
                fallbackCamera: _camera,
                controller: _viewportController,
                lightController: _lightController,
                modelController: _modelController,
              ),
            ),
          ),
          if (kDebugMode)
            Positioned(
              bottom: 72,
              right: 12,
              child: PhysicsDebugOverlay(bodies: _scene.debugBodies),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'JOLT PHYSICS',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Drag model to orbit  |  Pinch to zoom',
                    style: TextStyle(color: Color(0xff94a3b8)),
                  ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xaa071527),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xff38bdf8)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        _scene.touchStatus,
                        key: const ValueKey('touch-status'),
                        style: const TextStyle(color: Color(0xff7dd3fc)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      _camera.reset();
                      _viewportController.resetView();
                    },
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('Reset view'),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _scene.togglePause,
                        icon: Icon(
                          _scene.paused ? Icons.play_arrow : Icons.pause,
                        ),
                        label: Text(_scene.paused ? 'Resume' : 'Pause'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _scene.resetCube,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset model'),
                      ),
                    ],
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
