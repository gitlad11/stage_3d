import '../jolt_physics.dart';
import 'stage_component.dart';
import 'stage_object.dart';

/// Connects a [StageObject] to a Jolt rigid body.
///
/// Dynamic bodies write their latest simulated transform back to the owning
/// object's [TransformComponent]. Render components can then read the same
/// transform and keep visuals synchronized with physics.
final class PhysicsBodyComponent extends StageComponent {
  /// Creates a physics body component in [world].
  PhysicsBodyComponent(this.world, {required this.settings});

  /// Physics world that owns the body.
  final PhysicsWorld world;

  /// Body settings used when attaching to an object and when resetting.
  final RigidBodySettings settings;

  RigidBody? _body;

  /// Native Jolt body handle, if attached.
  RigidBody? get body => _body;

  /// Initial transform restored by [reset].
  PhysicsTransform get initialTransform => settings.transform;

  /// Current transform shared through the owning [StageObject].
  PhysicsTransform get transform =>
      object?.transform.transform ?? settings.transform;

  @override
  void onAttach(StageObject object) {
    object.transform.transform = settings.transform;
    _body = world.createBody(settings);
  }

  @override
  void update(double deltaSeconds) {
    final body = _body;
    final object = this.object;
    if (body == null || object == null) {
      return;
    }
    object.transform.transform = world.getTransform(body);
  }

  /// Applies an instantaneous physical push.
  void addImpulse(Vector3 impulse) {
    final body = _body;
    if (body != null) {
      world.addImpulse(body, impulse);
    }
  }

  /// Restores the initial transform and initial velocities.
  void reset() {
    final body = _body;
    final object = this.object;
    if (body == null) {
      return;
    }
    world
      ..setTransform(body, initialTransform)
      ..setLinearVelocity(body, settings.linearVelocity)
      ..setAngularVelocity(body, settings.angularVelocity);
    object?.transform.transform = initialTransform;
  }

  @override
  void onDetach() {
    final body = _body;
    if (body != null) {
      world.destroyBody(body);
      _body = null;
    }
  }
}
