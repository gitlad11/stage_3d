import 'vector3.dart';

/// A quaternion used to represent a three-dimensional rotation.
///
/// Prefer quaternions over Euler angles when synchronizing a rigid body with a
/// renderer. This avoids ambiguity and gimbal lock.
final class Quaternion {
  /// Creates a quaternion from its four components.
  const Quaternion(this.x, this.y, this.z, this.w);

  /// A rotation that leaves an object unchanged.
  static const identity = Quaternion(0, 0, 0, 1);

  /// The X component of the quaternion vector part.
  final double x;

  /// The Y component of the quaternion vector part.
  final double y;

  /// The Z component of the quaternion vector part.
  final double z;

  /// The scalar component of the quaternion.
  final double w;
}

/// The position and rotation of a rigid body in the physics world.
final class PhysicsTransform {
  /// Creates a transform at [position] with an optional [rotation].
  const PhysicsTransform({
    required this.position,
    this.rotation = Quaternion.identity,
  });

  /// The world-space position, conventionally measured in meters.
  final Vector3 position;

  /// The world-space orientation.
  final Quaternion rotation;

  /// Shortcut for `position.x`.
  double get x => position.x;

  /// Shortcut for `position.y`.
  double get y => position.y;

  /// Shortcut for `position.z`.
  double get z => position.z;

  /// Shortcut for `rotation.x`.
  double get qx => rotation.x;

  /// Shortcut for `rotation.y`.
  double get qy => rotation.y;

  /// Shortcut for `rotation.z`.
  double get qz => rotation.z;

  /// Shortcut for `rotation.w`.
  double get qw => rotation.w;
}
