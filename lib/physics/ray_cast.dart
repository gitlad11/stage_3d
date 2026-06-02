import 'dart:math' as math;

import 'rigid_body.dart';
import 'vector3.dart';

/// A finite world-space ray used for physics queries.
final class Ray {
  /// Creates a ray starting at [origin] and extending along [direction].
  ///
  /// [direction] does not need to be normalized.
  const Ray({
    required this.origin,
    required this.direction,
    required this.maxDistance,
  }) : assert(maxDistance > 0);

  /// Starting point in world coordinates.
  final Vector3 origin;

  /// Direction toward the queried objects.
  final Vector3 direction;

  /// Maximum query distance in world units.
  final double maxDistance;

  /// Unit-length direction used by the native adapter.
  Vector3 get normalizedDirection {
    final length = math.sqrt(
      direction.x * direction.x +
          direction.y * direction.y +
          direction.z * direction.z,
    );
    if (length == 0) {
      throw ArgumentError.value(direction, 'direction', 'must not be zero');
    }
    return Vector3(
      direction.x / length,
      direction.y / length,
      direction.z / length,
    );
  }

  /// Returns the world-space point at [fraction] along this ray.
  Vector3 pointAtFraction(double fraction) {
    final unit = normalizedDirection;
    return Vector3(
      origin.x + unit.x * maxDistance * fraction,
      origin.y + unit.y * maxDistance * fraction,
      origin.z + unit.z * maxDistance * fraction,
    );
  }
}

/// Closest rigid-body intersection returned by a ray cast.
final class RayCastHit {
  /// Creates an immutable hit result.
  const RayCastHit({
    required this.body,
    required this.position,
    required this.fraction,
    required this.distance,
  });

  /// Rigid body whose collider was hit.
  final RigidBody body;

  /// World-space intersection point.
  final Vector3 position;

  /// Intersection position from `0` to `1` along the finite ray.
  final double fraction;

  /// Distance from the ray origin in world units.
  final double distance;
}

/// Read-only spatial queries performed against a physics world.
abstract interface class PhysicsQueries {
  /// Finds the closest collider intersected by [ray], or returns `null`.
  RayCastHit? castRay(Ray ray);
}
