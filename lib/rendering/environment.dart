import '../physics/vector3.dart';

/// Reusable renderer environment settings for a scene.
///
/// Environment is separate from lights: lights describe emitters, while the
/// environment describes sky/background color and scene-wide reflection mood.
final class RenderEnvironment {
  /// Creates renderer environment settings.
  const RenderEnvironment({
    this.skyColor = const Vector3(0.16, 0.48, 0.78),
    this.skyAlpha = 1,
    this.ambientIntensity = 30000,
    this.reflectionIntensity = 0.9,
  }) : assert(skyAlpha >= 0 && skyAlpha <= 1),
       assert(ambientIntensity >= 0),
       assert(reflectionIntensity >= 0 && reflectionIntensity <= 1);

  /// RGB color used by the renderer skybox/background.
  final Vector3 skyColor;

  /// Skybox alpha.
  final double skyAlpha;

  /// Scene-wide ambient light hint for renderer backends.
  final double ambientIntensity;

  /// Reflection amount used by reflective procedural materials.
  final double reflectionIntensity;

  /// Serializes settings for the native renderer bridge.
  Map<String, Object> toMessage() => {
    'skyR': skyColor.x,
    'skyG': skyColor.y,
    'skyB': skyColor.z,
    'skyA': skyAlpha,
    'ambientIntensity': ambientIntensity,
    'reflectionIntensity': reflectionIntensity,
  };

  /// Returns a copy with selected values replaced.
  RenderEnvironment copyWith({
    Vector3? skyColor,
    double? skyAlpha,
    double? ambientIntensity,
    double? reflectionIntensity,
  }) {
    return RenderEnvironment(
      skyColor: skyColor ?? this.skyColor,
      skyAlpha: skyAlpha ?? this.skyAlpha,
      ambientIntensity: ambientIntensity ?? this.ambientIntensity,
      reflectionIntensity: reflectionIntensity ?? this.reflectionIntensity,
    );
  }
}
