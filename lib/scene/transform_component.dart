import '../physics/physics_transform.dart';
import '../physics/vector3.dart';
import 'stage_component.dart';

/// Shared transform component for scene objects.
///
/// Render and physics components can use this component as their synchronization
/// point: physics writes the latest body transform, rendering reads it.
final class TransformComponent extends StageComponent {
  /// Creates a transform component.
  TransformComponent({
    this.transform = const PhysicsTransform(position: Vector3.zero),
  });

  /// Current object transform in world space.
  PhysicsTransform transform;

  /// Current object position.
  Vector3 get position => transform.position;

  /// Current object rotation.
  Quaternion get rotation => transform.rotation;

  /// Moves this transform by component offsets.
  void translate(double dx, double dy, double dz) {
    transform = PhysicsTransform(
      position: transform.position.translate(dx, dy, dz),
      rotation: transform.rotation,
    );
  }
}
