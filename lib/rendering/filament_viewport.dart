import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jolt_physics.dart';
import '../scene/orbit_camera.dart';
import 'physics_scene_painter.dart';
import 'render_environment_controller.dart';
import 'render_light_controller.dart';
import 'render_model_controller.dart';
import 'render_scene_bridge.dart';
import 'stage_camera.dart';
import 'textured_mesh_prototype.dart';

/// Controls commands sent to the native Filament viewport.
///
/// This renderer bridge is separate from the reusable physics API.
final class FilamentViewportController {
  RenderSceneBridge? _bridge;
  OrbitCamera? _fallbackCamera;
  StageCamera _camera = StageCamera.defaultView;

  void attach(MethodChannel channel) {
    attachBridge(MethodChannelRenderSceneBridge(channel));
  }

  void attachBridge(RenderSceneBridge bridge) {
    _bridge = bridge;
    _bridge?.setCamera(_camera);
  }

  void detach() {
    _bridge = null;
    _fallbackCamera = null;
  }

  void attachFallbackCamera(OrbitCamera camera) {
    _fallbackCamera = camera;
    camera.setCamera(_camera, notify: false);
  }

  /// Applies a camera preset to the active renderer view.
  void setCamera(StageCamera camera) {
    _camera = camera;
    _fallbackCamera?.setCamera(camera);
    _bridge?.setCamera(camera);
  }

  void resetView() {
    setCamera(StageCamera.defaultView);
    _bridge?.resetView();
  }

  void orbitCamera(double deltaYaw, double deltaPitch) {
    _camera = _camera.orbitBy(deltaYaw, deltaPitch);
    _bridge?.orbitCamera(deltaYaw, deltaPitch);
  }

  void moveCamera(double deltaX, double deltaY) {
    _bridge?.moveCamera(deltaX, deltaY);
  }
}

/// Android Filament viewport registered by the Stage 3D plugin.
///
/// On non-Android platforms it falls back to a Flutter Canvas preview.
class FilamentViewport extends StatefulWidget {
  const FilamentViewport({
    super.key,
    required this.cube,
    required this.fallbackCamera,
    required this.controller,
    this.environmentController,
    required this.lightController,
    required this.modelController,
    required this.meshPrototypes,
    this.onRendererReady,
  });

  final PhysicsTransform cube;
  final OrbitCamera fallbackCamera;
  final FilamentViewportController controller;
  final RenderEnvironmentController? environmentController;
  final RenderLightController lightController;
  final RenderModelController modelController;
  final List<TexturedMeshPrototype> meshPrototypes;
  final VoidCallback? onRendererReady;

  @override
  State<FilamentViewport> createState() => _FilamentViewportState();
}

class _FilamentViewportState extends State<FilamentViewport> {
  MethodChannel? _channel;

  bool get _supportsFilament =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _onPlatformViewCreated(int viewId) {
    _channel = MethodChannel('filament_view_$viewId');
    final bridge = MethodChannelRenderSceneBridge(_channel!);
    widget.controller.attachBridge(bridge);
    widget.environmentController?.attachBridge(bridge);
    widget.lightController.attachBridge(bridge);
    for (final (index, mesh) in widget.meshPrototypes.indexed) {
      bridge.createTexturedMesh(index + 1, mesh);
    }
    widget.modelController.attachBridge(bridge);
    widget.controller.setCamera(widget.controller._camera);
    widget.onRendererReady?.call();
  }

  @override
  void dispose() {
    widget.controller.detach();
    widget.environmentController?.detach();
    widget.lightController.detach();
    widget.modelController.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_supportsFilament) {
      return AndroidView(
        viewType: 'jolt_filament_view',
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) => widget.fallbackCamera.beginGesture(),
      onScaleUpdate: widget.fallbackCamera.updateGesture,
      child: CustomPaint(
        painter: PhysicsScenePainter(
          cube: widget.cube,
          camera: widget.fallbackCamera,
          meshPrototypes: widget.meshPrototypes,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.controller.attachFallbackCamera(widget.fallbackCamera);
  }
}
