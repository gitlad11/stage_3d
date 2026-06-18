import 'package:flutter/foundation.dart';

import '../jolt_physics.dart';
import 'physics_body_component.dart';
import 'stage_object.dart';
import 'stage_scene.dart';

final class PhysicsScene extends ChangeNotifier {
  PhysicsScene({
    PhysicsWorld? world,
    ColliderShape modelShape = const CompoundShape([
      PositionedShape(shape: CapsuleShape(halfHeight: 0.65, radius: 0.45)),
      PositionedShape(
        shape: BoxShape(halfWidth: 0.32, halfHeight: 0.14, halfDepth: 0.28),
        position: Vector3(0, -1.05, 0),
      ),
    ]),
  }) : _world = world ?? createPhysicsWorld() {
    stage = StageScene();
    floor = _world.createBody(
      const RigidBodySettings(
        shape: BoxShape(halfWidth: 8, halfHeight: 0.25, halfDepth: 8),
        motionType: MotionType.static,
        transform: PhysicsTransform(position: Vector3(0, -0.25, 0)),
      ),
    );
    const initialTransform = PhysicsTransform(position: Vector3(0, 5.5, 0));
    modelObject = stage.add(
      StageObject.node('fox', transform: initialTransform),
    );
    model = modelObject.add(
      PhysicsBodyComponent(
        _world,
        settings: RigidBodySettings(
          shape: modelShape,
          motionType: MotionType.dynamic,
          transform: initialTransform,
          angularVelocity: Vector3.zero,
          friction: 0.65,
          restitution: 0.35,
        ),
      ),
    );
  }

  final PhysicsWorld _world;
  late final StageScene stage;
  late final RigidBody floor;
  late final StageObject modelObject;
  late final PhysicsBodyComponent model;
  bool _paused = false;
  String _touchStatus = 'Tap the fox collider';

  String get engineLabel => _world.engineLabel;

  bool get paused => _paused;

  String get touchStatus => _touchStatus;

  List<RigidBodySnapshot> get debugBodies => _world.snapshotBodies();

  void step(double deltaSeconds) {
    if (_paused) {
      return;
    }
    _world.step(deltaSeconds);
    stage.update(deltaSeconds);
    notifyListeners();
  }

  void togglePause() {
    _paused = !_paused;
    notifyListeners();
  }

  void resetCube() {
    model.reset();
    notifyListeners();
  }

  void addCubeImpulse(double x, double y, double z) {
    model.addImpulse(Vector3(x, y, z));
    notifyListeners();
  }

  /// Casts a vertical Jolt-only ray through the current model position.
  ///
  /// The demo uses this as a minimal tap event prototype before screen-space
  /// camera unprojection is added. Rendering is not involved in the query.
  void castRayAtModel() {
    final position = model.transform.position;
    final hit = _world.queries.castRay(
      Ray(
        origin: position.translate(0, 2, 0),
        direction: const Vector3(0, -1, 0),
        maxDistance: 4,
      ),
    );
    _touchStatus = hit?.body == model.body
        ? 'Touched grass'
        : 'Ray missed fox collider';
    notifyListeners();
  }

  @override
  void dispose() {
    stage.dispose();
    _world.dispose();
    super.dispose();
  }
}
