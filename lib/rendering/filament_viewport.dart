import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jolt_physics.dart';
import '../scene/orbit_camera.dart';
import 'physics_scene_painter.dart';
import 'render_light_controller.dart';
import 'render_model_controller.dart';

/// Controls commands sent to the native Filament demo viewport.
///
/// This renderer bridge is separate from the reusable physics API.
final class FilamentViewportController {
  MethodChannel? _channel;

  void attach(MethodChannel channel) {
    _channel = channel;
  }

  void detach() {
    _channel = null;
  }

  void resetView() {
    _channel?.invokeMethod<void>('resetView');
  }
}

/// Android Filament viewport used by the example application.
///
/// On non-Android platforms it falls back to a Flutter Canvas preview.
class FilamentViewport extends StatefulWidget {
  const FilamentViewport({
    super.key,
    required this.cube,
    required this.fallbackCamera,
    required this.controller,
    required this.lightController,
    required this.modelController,
  });

  final PhysicsTransform cube;
  final OrbitCamera fallbackCamera;
  final FilamentViewportController controller;
  final RenderLightController lightController;
  final RenderModelController modelController;

  @override
  State<FilamentViewport> createState() => _FilamentViewportState();
}

class _FilamentViewportState extends State<FilamentViewport> {
  MethodChannel? _channel;

  bool get _supportsFilament =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _onPlatformViewCreated(int viewId) {
    _channel = MethodChannel('filament_view_$viewId');
    widget.controller.attach(_channel!);
    widget.lightController.attach(_channel!);
    widget.modelController.attach(_channel!);
  }

  @override
  void dispose() {
    widget.controller.detach();
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
        ),
      ),
    );
  }
}
