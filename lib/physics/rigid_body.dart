import 'collider_shape.dart';
import 'physics_transform.dart';
import 'vector3.dart';

/// Defines how Jolt moves and simulates a rigid body.
enum MotionType {
  /// A body that never moves, such as a floor, wall, or level mesh.
  static(0),

  /// A body controlled by game code that can push dynamic bodies.
  ///
  /// Move kinematic bodies with [PhysicsWorld.moveKinematic].
  kinematic(1),

  /// A fully simulated body affected by gravity, contacts, and impulses.
  dynamic(2);

  const MotionType(this.nativeValue);

  /// Internal value passed to the native Jolt adapter.
  final int nativeValue;
}

/// Stable identifier for a native Jolt body inside one physics world.
///
/// Do not reuse a [BodyId] after destroying its [RigidBody].
final class BodyId {
  /// Creates an identifier from the native Jolt body handle.
  const BodyId(this.value);

  /// Native body index and sequence number encoded by Jolt.
  final int value;
}

/// Describes a rigid body before it is inserted into a [PhysicsWorld].
final class RigidBodySettings {
  /// Creates immutable body settings.
  const RigidBodySettings({
    required this.shape,
    required this.motionType,
    required this.transform,
    this.linearVelocity = Vector3.zero,
    this.angularVelocity = Vector3.zero,
    this.friction = 0.5,
    this.restitution = 0,
    this.isSensor = false,
  }) : assert(friction >= 0),
       assert(restitution >= 0);

  /// Invisible collision geometry used by Jolt.
  final ColliderShape shape;

  /// Determines whether the body is static, kinematic, or dynamic.
  final MotionType motionType;

  /// Initial world-space position and orientation.
  final PhysicsTransform transform;

  /// Initial movement in world units per second.
  final Vector3 linearVelocity;

  /// Initial rotation speed in radians per second.
  final Vector3 angularVelocity;

  /// Surface friction coefficient.
  final double friction;

  /// Surface bounciness coefficient.
  final double restitution;

  /// Whether the body reports overlaps without producing collision response.
  final bool isSensor;
}

/// Handle for a body owned by a [PhysicsWorld].
///
/// The body settings remain available for reset logic and application metadata.
/// The live transform and velocities must be read from the owning world.
final class RigidBody {
  /// Creates a body handle from its native [id] and original [settings].
  const RigidBody({required this.id, required this.settings});

  /// Identifier used for native world operations.
  final BodyId id;

  /// Immutable settings used when the body was created.
  final RigidBodySettings settings;
}

/// Immutable debug view of a live rigid body.
///
/// Snapshots are useful for debug overlays, inspectors, and logging. They do
/// not own native resources and become stale after the next simulation step.
final class RigidBodySnapshot {
  /// Creates a snapshot of [body] at [transform].
  const RigidBodySnapshot({required this.body, required this.transform});

  /// Live body handle and immutable creation settings.
  final RigidBody body;

  /// World-space transform captured when the snapshot was requested.
  final PhysicsTransform transform;
}
