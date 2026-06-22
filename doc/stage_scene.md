# Stage Scene Runtime

`StageScene` is the first high-level scene layer above the lower-level physics,
rendering, input, and material APIs.

It is intentionally small:

- `StageScene` owns scene objects and calls `update(deltaSeconds)`;
- `StageObject` has a stable name and a required `TransformComponent`;
- `StageComponent` is the base lifecycle hook for reusable behavior;
- `TransformComponent` is the shared synchronization point for future physics
  and rendering components.

## Basic Object

```dart
final scene = StageScene();

final fox = scene.add(StageObject('fox'));
fox.transform.translate(0, 1, 0);

scene.update(1 / 60);
```

## Custom Component

```dart
final class SpinComponent extends StageComponent {
  var elapsed = 0.0;

  @override
  void update(double deltaSeconds) {
    elapsed += deltaSeconds;
  }
}

final fox = StageObject('fox')..add(SpinComponent());
scene.add(fox);
```

Component lifecycle:

- `onAttach(object)` after a component is added;
- `update(deltaSeconds)` each scene tick;
- `onDetach()` when removed or disposed.

Call `StageObject.dispose()` or `StageScene.dispose()` when objects leave the
screen. This gives components a chance to release native resources, such as a
Filament model instance or a Jolt rigid body.

## Node-Style Objects

`StageObject.node` creates a Godot-like node: the object has one world
transform, and components attached to it can represent local models, physics,
lights, scripts, or other behavior.

```dart
final fox = StageObject.node(
  'fox',
  transform: const PhysicsTransform(position: Vector3(0, 5, 0)),
  components: [
    PhysicsBodyComponent(
      world,
      settings: const RigidBodySettings(
        shape: CompoundShape([
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
        ]),
        motionType: MotionType.dynamic,
        transform: PhysicsTransform(position: Vector3(0, 5, 0)),
      ),
    ),
    PositionedModel(
      asset: foxAsset,
      position: Vector3(0, 0.2, 0),
    ).toComponent(modelController),
  ],
);
```

The node transform is the object's world position. `PositionedShape` and
`PositionedModel` use local coordinates inside that object, so several physical
and visual parts can move as one object.

When this node is removed with `scene.remove(fox)` or the whole scene is closed
with `scene.dispose()`, attached components receive `onDetach()`. The built-in
physics and render model components use that hook to destroy their Jolt body or
Filament model instance.

## Why This Layer Exists

Before this layer, demo code had to manually connect physics, rendering, input,
lights, and camera behavior inside a widget tick function. `StageScene` makes
the runtime component-friendly without forcing a specific ECS design yet.

The next layer can add concrete components such as:

- `RigidBodyComponent`;
- `RenderModelComponent`;
- `AnimationComponent`;
- `LightComponent`;
- `CameraControllerComponent`;
- `ScriptComponent`.
