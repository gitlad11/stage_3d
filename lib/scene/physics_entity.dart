import '../jolt_physics.dart';

/// Demo-level object that couples a reusable [RigidBody] with reset behavior.
///
/// Applications can build their own entity classes around [PhysicsWorld] and
/// [RigidBody]. This class is intentionally small and is not required by the
/// core physics API.
final class PhysicsEntity {
  /// Creates an entity owned by [_world].
  PhysicsEntity(
    this._world, {
    required this.body,
    required this.initialTransform,
  });

  final PhysicsWorld _world;

  /// The native body represented by this entity.
  final RigidBody body;

  /// Transform restored by [reset].
  final PhysicsTransform initialTransform;

  /// Reads the current transform from Jolt.
  PhysicsTransform get transform => _world.getTransform(body);

  /// Applies an instantaneous physical push.
  void addImpulse(Vector3 impulse) {
    _world.addImpulse(body, impulse);
  }

  /// Restores the initial transform and initial velocities.
  void reset() {
    _world
      ..setTransform(body, initialTransform)
      ..setLinearVelocity(body, body.settings.linearVelocity)
      ..setAngularVelocity(body, body.settings.angularVelocity);
  }
}
