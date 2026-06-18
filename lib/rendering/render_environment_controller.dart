import 'package:flutter/services.dart';

import 'environment.dart';
import 'render_scene_bridge.dart';

/// Manages scene-wide renderer environment settings.
///
/// This controller is intentionally separate from [RenderLightController]:
/// lights are individual objects, while an environment configures the sky,
/// ambient mood, and reflection strength for the whole viewport.
final class RenderEnvironmentController {
  RenderSceneBridge? _bridge;
  RenderEnvironment _environment;

  /// Creates a controller with an initial [environment].
  RenderEnvironmentController({RenderEnvironment? initialEnvironment})
    : _environment = initialEnvironment ?? const RenderEnvironment();

  /// Current Dart-side environment settings.
  RenderEnvironment get environment => _environment;

  /// Attaches this controller to an initialized native viewport.
  void attach(MethodChannel channel) {
    attachBridge(MethodChannelRenderSceneBridge(channel));
  }

  /// Attaches this controller to a renderer bridge.
  void attachBridge(RenderSceneBridge bridge) {
    _bridge = bridge;
    _bridge?.setEnvironment(_environment);
  }

  /// Detaches from the native viewport while preserving Dart settings.
  void detach() {
    _bridge = null;
  }

  /// Replaces environment settings and applies them to the renderer.
  void setEnvironment(RenderEnvironment environment) {
    _environment = environment;
    _bridge?.setEnvironment(environment);
  }
}
