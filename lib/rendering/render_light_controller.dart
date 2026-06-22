import 'package:flutter/services.dart';

import '../physics/vector3.dart';
import 'light.dart';
import 'render_scene_bridge.dart';

/// Manages lights in the native Filament viewport.
///
/// The API deliberately lives outside [PhysicsWorld]. Rendering and physics are
/// independent systems, so applications may attach a light to a rigid body,
/// animate it directly, or leave it static.
final class RenderLightController {
  RenderSceneBridge? _bridge;
  var _nextId = 1;
  final _lights = <int, RenderLight>{};

  /// Attaches this controller to an initialized native viewport.
  ///
  /// Existing lights are created in the newly attached renderer.
  void attach(MethodChannel channel) {
    attachBridge(MethodChannelRenderSceneBridge(channel));
  }

  /// Attaches this controller to a renderer bridge.
  void attachBridge(RenderSceneBridge bridge) {
    _bridge = bridge;
    for (final light in _lights.values) {
      _createBridgeLight(light);
    }
  }

  /// Detaches from the native viewport while preserving Dart light settings.
  void detach() {
    _bridge = null;
  }

  /// Creates a render light from [settings].
  RenderLight createLight(Light settings) {
    final light = RenderLight(id: LightId(_nextId++), settings: settings);
    _lights[light.id.value] = light;
    _createBridgeLight(light);
    return light;
  }

  /// Moves a point [light] to [position].
  ///
  /// Directional lights do not have a position.
  void setPosition(RenderLight light, Vector3 position) {
    _bridge?.setLightPosition(light.id, position);
  }

  /// Changes the travel direction of a directional [light].
  void setDirection(RenderLight light, Vector3 direction) {
    _bridge?.setLightDirection(light.id, direction);
  }

  /// Changes the luminous intensity of [light].
  void setIntensity(RenderLight light, double intensity) {
    _bridge?.setLightIntensity(light.id, intensity);
  }

  /// Removes [light] from Dart and the native renderer.
  void destroyLight(RenderLight light) {
    _lights.remove(light.id.value);
    _bridge?.destroyLight(light.id);
  }

  void _createBridgeLight(RenderLight light) {
    _bridge?.createLight(light);
  }
}
