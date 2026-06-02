import 'package:flutter_test/flutter_test.dart';
import 'package:stage_3d/jolt_physics.dart';

void main() {
  test('world exposes generic static, dynamic and kinematic bodies', () {
    final world = createPhysicsWorld();
    addTearDown(world.dispose);

    final floor = world.createBody(
      const RigidBodySettings(
        shape: BoxShape(halfWidth: 8, halfHeight: 0.25, halfDepth: 8),
        motionType: MotionType.static,
        transform: PhysicsTransform(position: Vector3(0, -0.25, 0)),
      ),
    );
    final ball = world.createBody(
      const RigidBodySettings(
        shape: SphereShape(radius: 0.5),
        motionType: MotionType.dynamic,
        transform: PhysicsTransform(position: Vector3(0, 3, 0)),
      ),
    );
    final platform = world.createBody(
      const RigidBodySettings(
        shape: BoxShape(halfWidth: 1, halfHeight: 0.2, halfDepth: 1),
        motionType: MotionType.kinematic,
        transform: PhysicsTransform(position: Vector3(0, 1, 0)),
      ),
    );

    world
      ..addImpulse(ball, const Vector3(1, 0, 0))
      ..moveKinematic(
        platform,
        const PhysicsTransform(position: Vector3(2, 1, 0)),
        1 / 60,
      )
      ..step(1 / 60);

    expect(world.getTransform(ball).position.x, greaterThan(0));
    expect(world.getLinearVelocity(ball).x, 1);
    expect(world.getTransform(platform).position.x, 2);
    expect(world.snapshotBodies(), hasLength(3));

    world
      ..destroyBody(ball)
      ..destroyBody(platform)
      ..destroyBody(floor);

    expect(world.snapshotBodies(), isEmpty);
  });

  test('ray queries return the closest rigid body hit', () {
    final world = createPhysicsWorld();
    addTearDown(world.dispose);

    final sphere = world.createBody(
      const RigidBodySettings(
        shape: SphereShape(radius: 1),
        motionType: MotionType.static,
        transform: PhysicsTransform(position: Vector3(0, 0, 5)),
      ),
    );

    final hit = world.queries.castRay(
      const Ray(
        origin: Vector3.zero,
        direction: Vector3(0, 0, 1),
        maxDistance: 10,
      ),
    );

    expect(hit?.body, same(sphere));
    expect(hit?.position.z, closeTo(4, 0.0001));
    expect(hit?.distance, closeTo(4, 0.0001));
    expect(hit?.fraction, closeTo(0.4, 0.0001));
  });
}
