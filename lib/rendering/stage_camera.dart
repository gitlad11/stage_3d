import 'dart:math' as math;

import '../physics/vector3.dart';

/// Reusable orbit camera preset for renderer view switching.
///
/// Keep several [StageCamera] values in app state and pass the active one to
/// `FilamentViewportController.setCamera` when the user changes view mode.
final class StageCamera {
  /// Creates an orbit camera around [target].
  const StageCamera.orbit({
    this.target = Vector3.zero,
    this.yaw = 0,
    this.pitch = 0,
    this.distance = 4,
  }) : assert(distance > 0);

  /// Default renderer camera used by the Android Filament viewport.
  static const defaultView = StageCamera.orbit();

  /// Point the camera orbits around.
  final Vector3 target;

  /// Horizontal orbit angle in radians.
  final double yaw;

  /// Vertical orbit angle in radians.
  final double pitch;

  /// Distance from [target].
  final double distance;

  /// World-space eye position derived from the orbit settings.
  Vector3 get eye {
    final horizontal = math.cos(pitch) * distance;
    return Vector3(
      target.x + math.sin(yaw) * horizontal,
      target.y + math.sin(pitch) * distance,
      target.z + math.cos(yaw) * horizontal,
    );
  }

  /// Returns a camera rotated by [deltaYaw] and [deltaPitch].
  StageCamera orbitBy(double deltaYaw, double deltaPitch) => copyWith(
    yaw: yaw + deltaYaw,
    pitch: (pitch + deltaPitch).clamp(-1.45, 1.45).toDouble(),
  );

  /// Returns a camera with selected values replaced.
  StageCamera copyWith({
    Vector3? target,
    double? yaw,
    double? pitch,
    double? distance,
  }) {
    return StageCamera.orbit(
      target: target ?? this.target,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      distance: distance ?? this.distance,
    );
  }

  /// Serializes settings for the native renderer bridge.
  Map<String, Object> toMessage() => {
    'targetX': target.x,
    'targetY': target.y,
    'targetZ': target.z,
    'yaw': yaw,
    'pitch': pitch,
    'distance': distance,
  };

  @override
  bool operator ==(Object other) =>
      other is StageCamera &&
      other.target == target &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.distance == distance;

  @override
  int get hashCode => Object.hash(target, yaw, pitch, distance);
}
