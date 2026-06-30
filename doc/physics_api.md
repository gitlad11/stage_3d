# Stage 3D Physics API Guide

Stage 3D is a Flutter runtime for prototyping interactive 3D scenes with native
rendering, physics, animations, lighting, and spatial queries. Its Android
physics layer calls Jolt Physics through a C++ `dart:ffi` adapter.

Import the public API from one entrypoint:

```dart
import 'package:stage_3d/stage_3d.dart';
```

## Coordinate System

The API follows the Jolt demo convention:

```text
X  horizontal axis
Y  vertical axis, positive direction is up
Z  depth axis
```

One world unit should be treated as one meter. Jolt applies gravity while
advancing the world.

## Create A World

```dart
final world = createPhysicsWorld();

// Call this when the owning screen, game, or service is disposed.
world.dispose();
```

A body belongs to the world that created it. Do not pass a `RigidBody` to a
different world.

## Collider Shapes

Shapes describe invisible collision geometry. They are independent from visual
models such as `.glb` assets.

```dart
const box = BoxShape(
  halfWidth: 1,
  halfHeight: 0.25,
  halfDepth: 1,
);

const character = CapsuleShape(
  halfHeight: 0.65,
  radius: 0.45,
);

const ball = SphereShape(radius: 0.5);

const barrel = CylinderShape(
  halfHeight: 0.75,
  radius: 0.4,
);
```

Box and cylinder sizes use half-extents. For example, a box with
`halfWidth: 1` has a total width of two meters.

## Compound Colliders

Use `CompoundShape` when one primitive collider is not enough. Each
`PositionedShape` is placed in local coordinates relative to the rigid body's
world transform.

```dart
const foxCollider = CompoundShape([
  PositionedShape(
    shape: CapsuleShape(halfHeight: 0.65, radius: 0.45),
  ),
  PositionedShape(
    shape: BoxShape(
      halfWidth: 0.32,
      halfHeight: 0.14,
      halfDepth: 0.28,
    ),
    position: Vector3(0, -1.05, 0),
  ),
]);
```

This is useful for characters, vehicles, furniture, and other models where a
single capsule or box either floats above the ground or cuts through visible
geometry.

## Motion Types

| Motion type | Use case |
| --- | --- |
| `MotionType.static` | Floors, walls, and level geometry that never move |
| `MotionType.kinematic` | Scripted platforms and doors that push dynamic bodies |
| `MotionType.dynamic` | Fully simulated bodies affected by gravity and impulses |

## Static Floor

```dart
final floor = world.createBody(
  const RigidBodySettings(
    shape: BoxShape(
      halfWidth: 8,
      halfHeight: 0.25,
      halfDepth: 8,
    ),
    motionType: MotionType.static,
    transform: PhysicsTransform(
      position: Vector3(0, -0.25, 0),
    ),
  ),
);
```

## Dynamic Ball

```dart
final ball = world.createBody(
  const RigidBodySettings(
    shape: SphereShape(radius: 0.5),
    motionType: MotionType.dynamic,
    transform: PhysicsTransform(
      position: Vector3(0, 4, 0),
    ),
    friction: 0.6,
    restitution: 0.35,
  ),
);

world.addImpulse(ball, const Vector3(2, 4, 0));
```

## Kinematic Platform

Kinematic bodies are controlled by application code. Use `moveKinematic`
instead of teleporting the body each frame so Jolt can calculate interaction
velocities.

```dart
final platform = world.createBody(
  const RigidBodySettings(
    shape: BoxShape(
      halfWidth: 2,
      halfHeight: 0.2,
      halfDepth: 2,
    ),
    motionType: MotionType.kinematic,
    transform: PhysicsTransform(
      position: Vector3(0, 1, 0),
    ),
  ),
);

world.moveKinematic(
  platform,
  const PhysicsTransform(
    position: Vector3(3, 1, 0),
  ),
  1 / 60,
);
```

## Game Loop

Advance the physics world before sending body transforms to a renderer:

```dart
void tick(double deltaSeconds) {
  world.step(deltaSeconds);

  final transform = world.getTransform(ball);
  final velocity = world.getLinearVelocity(ball);

  renderer.setTransform(
    position: transform.position,
    rotation: transform.rotation,
  );
}
```

## Teleport, Velocity, Or Impulse?

| Method | Meaning |
| --- | --- |
| `setTransform` | Spawn, reset, or teleport a body |
| `setLinearVelocity` | Replace the current movement directly |
| `setAngularVelocity` | Replace the current rotation speed directly |
| `addImpulse` | Apply a physical push to a dynamic body |
| `moveKinematic` | Move a scripted kinematic body while preserving interactions |

## Rendering With Filament

Jolt does not render 3D graphics. The included Android demo uses Filament:

```text
Jolt C++ simulation
        |
        | body transform through Dart FFI
        v
Flutter scene
        |
        | MethodChannel
        v
Filament Android Platform View
        |
        v
animated Fox.glb model
```

The renderer and physics engine intentionally remain separate. A `.glb` model
can use a capsule, box, or compound collider depending on gameplay needs. For
renderer-side light prototypes, see [Rendering lights](rendering_lights.md).

## Reusable Model Assets

Visual assets are separate from rigid bodies. Register a GLB file once, then
create one or more instances:

```dart
import 'package:stage_3d/stage_3d.dart';

final models = RenderModelController();

final chairAsset = models.loadAsset(
  const ModelAsset(assetPath: 'models/chair.glb'),
);

final chairA = models.createInstance(
  chairAsset,
  transform: const PhysicsTransform(
    position: Vector3(1, 0, 2),
  ),
);

final chairB = models.createInstance(
  chairAsset,
  transform: const PhysicsTransform(
    position: Vector3(3, 0, 2),
  ),
);
```

Move an instance directly:

```dart
models.setTransform(
  chairA,
  const PhysicsTransform(position: Vector3(2, 0, 1)),
);
```

Or bind it to a Jolt body in the application loop:

```dart
void tick(double deltaSeconds) {
  world.step(deltaSeconds);
  models.setTransform(chairA, world.getTransform(chairBody));
}
```

### Model Animations

GLB animation clips can be inspected and controlled per visible model
instance:

```dart
final clips = await models.getAnimations(character);
for (final clip in clips) {
  print('${clip.index}: ${clip.name} (${clip.durationSeconds}s)');
}

models.playAnimation(
  character,
  animationIndex: clips.first.index,
  loop: true,
  speed: 1,
);

models.pauseAnimation(character);
models.resumeAnimation(character);
models.stopAnimation(character);
```

Instances created from the same GLB asset keep independent playback state. An
optional `ModelAsset.animationIndex` selects the initial looping clip.

### Architectural Scenes

For a property visualization app, a scene can combine:

```text
room.glb        one static room shell
chair.glb       many visual instances
table.glb       one or more visual instances
lights         independent directional and point light prototypes
rigid bodies   optional colliders only where interaction is needed
```

A room shell does not need a rigid body when it is only displayed. Add Jolt
colliders for walls, floors, doors, or furniture only when users need collision,
movement, or interaction.

Filament currently loads `.glb` files from Android assets. Convert `.fbx`,
`.obj`, `.blend`, and other source formats to `.glb` during content preparation.

## Ray Casting

Ray casting is exposed as a separate read-only query interface:

```dart
final hit = world.queries.castRay(
  const Ray(
    origin: Vector3(0, 2, -5),
    direction: Vector3(0, 0, 1),
    maxDistance: 100,
  ),
);

if (hit != null) {
  print(hit.body.id.value);
  print(hit.position);
}
```

On Android, Jolt performs a narrow-phase cast against the actual collider
shapes. This is useful for selecting a rendered model through its associated
rigid body. The non-Android preview backend uses approximate bounding spheres.

## Current Prototype Limits

- Android is the only platform backed by Jolt.
- Other platforms use a lightweight preview backend for tests and UI work.
- The public shape API currently includes box, capsule, sphere, cylinder, and
  compound colliders.
- Collision callbacks, constraints, mesh shapes, character
  controllers, query filters, and multi-hit ray casts are not exposed yet.
- The demo synchronizes both Jolt position and quaternion with the Filament
  visual model.

## Debug Collider Inspector

Debug Flutter builds display a collider inspector above the Filament viewport.
It is guarded by `kDebugMode`, so it is excluded from release builds.

The inspector uses:

```dart
final snapshots = world.snapshotBodies();
```

Each `RigidBodySnapshot` contains the live body handle, immutable creation
settings, collider shape, motion type, and current transform. The included
overlay renders a compact stable top-down `X/Z` map with `BodyId` labels.

The top-down map intentionally remains independent from the native Filament
orbit camera. This keeps it readable while inspecting the physics world from
different visual camera angles.
