import '../physics/vector3.dart';

/// Stable identifier for a light owned by a renderer.
final class LightId {
  /// Creates a renderer light identifier.
  const LightId(this.value);

  /// Renderer-specific identifier.
  final int value;
}

/// Base class for reusable render light settings.
///
/// Lights belong to the rendering layer, not to Jolt Physics. To create a
/// physical lamp, keep a [Light] and a rigid body as separate objects and copy
/// the body's position to the light each frame.
sealed class Light {
  /// Creates common light settings.
  const Light({
    this.color = const Vector3(1, 1, 1),
    required this.intensity,
    this.castShadows = true,
  }) : assert(intensity >= 0);

  /// RGB color components in the range expected by the renderer.
  final Vector3 color;

  /// Luminous intensity interpreted by the active renderer.
  final double intensity;

  /// Whether this light should cast shadows.
  final bool castShadows;

  /// Internal identifier passed to the native renderer.
  int get nativeType;

  /// Serializes settings for the native renderer bridge.
  Map<String, Object> toMessage();
}

/// A light source infinitely far away, described only by its direction.
///
/// Use directional lights for sunlight and broad outdoor illumination.
final class DirectionalLight extends Light {
  /// Creates a directional light.
  const DirectionalLight({
    required this.direction,
    super.color,
    super.intensity = 100000,
    super.castShadows,
  });

  /// Direction in which the light travels.
  final Vector3 direction;

  @override
  int get nativeType => 0;

  @override
  Map<String, Object> toMessage() => {
    'type': nativeType,
    'dx': direction.x,
    'dy': direction.y,
    'dz': direction.z,
    'r': color.x,
    'g': color.y,
    'b': color.z,
    'intensity': intensity,
    'castShadows': castShadows,
  };
}

/// A local light source that emits in every direction from [position].
///
/// Use point lights for lamps, glowing objects, and movable light sources.
final class PointLight extends Light {
  /// Creates a point light.
  const PointLight({
    required this.position,
    super.color,
    super.intensity = 1000,
    this.falloffRadius = 10,
    super.castShadows,
  }) : assert(falloffRadius > 0);

  /// World-space position of the source.
  final Vector3 position;

  /// Radius beyond which the light no longer contributes.
  final double falloffRadius;

  @override
  int get nativeType => 1;

  @override
  Map<String, Object> toMessage() => {
    'type': nativeType,
    'x': position.x,
    'y': position.y,
    'z': position.z,
    'r': color.x,
    'g': color.y,
    'b': color.z,
    'intensity': intensity,
    'falloffRadius': falloffRadius,
    'castShadows': castShadows,
  };
}

/// Renderer handle paired with the immutable settings used to create it.
final class RenderLight {
  /// Creates a render light handle.
  const RenderLight({required this.id, required this.settings});

  /// Identifier used for renderer operations.
  final LightId id;

  /// Initial renderer settings.
  final Light settings;
}
