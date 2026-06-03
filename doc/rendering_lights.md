# Rendering Lights

Lighting belongs to the renderer rather than to Jolt Physics. Stage 3D exposes
reusable Dart prototypes for directional and point lights that the Android
Filament viewport can consume.

## Directional And Point Lights

```dart
import 'package:stage_3d/rendering/light.dart';
import 'package:stage_3d/rendering/render_light_controller.dart';

final lights = RenderLightController();

final sun = lights.createLight(
  const DirectionalLight(
    direction: Vector3(0, -0.5, -1),
    intensity: 120000,
  ),
);

final lamp = lights.createLight(
  const PointLight(
    position: Vector3(2, 4, 1),
    intensity: 1500,
    falloffRadius: 8,
  ),
);

lights.setPosition(lamp, const Vector3(3, 5, 0));
lights.setIntensity(sun, 90000);
lights.destroyLight(lamp);
```

The `RenderLightController` attaches to the native Filament viewport in the
demo. Applications can keep the same light prototype and implement another
renderer bridge later.

## Physical Lamp

A lamp that falls or collides needs two independent objects: a Jolt rigid body
for physics and a Filament light for rendering.

```dart
final lampBody = world.createBody(
  const RigidBodySettings(
    shape: SphereShape(radius: 0.2),
    motionType: MotionType.dynamic,
    transform: PhysicsTransform(
      position: Vector3(0, 4, 0),
    ),
  ),
);

final lampLight = lights.createLight(
  const PointLight(
    position: Vector3(0, 4, 0),
    intensity: 1500,
  ),
);

void tick(double deltaSeconds) {
  world.step(deltaSeconds);
  lights.setPosition(lampLight, world.getTransform(lampBody).position);
}
```

Jolt moves the rigid body. Filament moves the light. The game layer performs
the synchronization.
