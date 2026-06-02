import 'package:flutter/services.dart';

import '../physics/vector3.dart';
import 'light.dart';

/// Manages lights in the native Filament demo viewport.
///
/// The API deliberately lives outside [PhysicsWorld]. Rendering and physics are
/// independent systems, so applications may attach a light to a rigid body,
/// animate it directly, or leave it static.
final class RenderLightController {
  MethodChannel? _channel;
  var _nextId = 1;
  final _lights = <int, RenderLight>{};

  /// Attaches this controller to an initialized native viewport.
  ///
  /// Existing lights are created in the newly attached renderer.
  void attach(MethodChannel channel) {
    _channel = channel;
    for (final light in _lights.values) {
      _createNativeLight(light);
    }
  }

  /// Detaches from the native viewport while preserving Dart light settings.
  void detach() {
    _channel = null;
  }

  /// Creates a render light from [settings].
  RenderLight createLight(Light settings) {
    final light = RenderLight(id: LightId(_nextId++), settings: settings);
    _lights[light.id.value] = light;
    _createNativeLight(light);
    return light;
  }

  /// Moves a point [light] to [position].
  ///
  /// Directional lights do not have a position.
  void setPosition(RenderLight light, Vector3 position) {
    _channel?.invokeMethod<void>('setLightPosition', {
      'id': light.id.value,
      'x': position.x,
      'y': position.y,
      'z': position.z,
    });
  }

  /// Changes the travel direction of a directional [light].
  void setDirection(RenderLight light, Vector3 direction) {
    _channel?.invokeMethod<void>('setLightDirection', {
      'id': light.id.value,
      'x': direction.x,
      'y': direction.y,
      'z': direction.z,
    });
  }

  /// Changes the luminous intensity of [light].
  void setIntensity(RenderLight light, double intensity) {
    _channel?.invokeMethod<void>('setLightIntensity', {
      'id': light.id.value,
      'intensity': intensity,
    });
  }

  /// Removes [light] from Dart and the native renderer.
  void destroyLight(RenderLight light) {
    _lights.remove(light.id.value);
    _channel?.invokeMethod<void>('destroyLight', {'id': light.id.value});
  }

  void _createNativeLight(RenderLight light) {
    _channel?.invokeMethod<void>('createLight', {
      'id': light.id.value,
      ...light.settings.toMessage(),
    });
  }
}
