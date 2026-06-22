# Stage 3D

**Stage 3D is a Flutter 3D Gateway API for building interactive 3D experiences
with native rendering, physics, assets, animation, lighting, scene components,
and spatial queries.**

Stage 3D connects Flutter apps to native 3D capabilities through a reusable
gateway API. Use the component-friendly `StageScene` runtime, build your own
scene layer, or use the rendering, physics, input, material, lighting,
animation, and spatial query APIs independently inside any Flutter UI.

Stage 3D currently combines
[Jolt Physics](https://github.com/jrouwe/JoltPhysics) `v5.5.0` with
[Filament](https://github.com/google/filament) rendering on Android.

Support & Contact: [efimovi420@gmail.com](mailto:efimovi420@gmail.com)

If Stage 3D helps your project, please consider starring the repository.

## Native Backends

Stage 3D ships with native Android integrations for two separate systems:

- **Jolt Physics** through a C++ `dart:ffi` adapter for simulation, rigid
  bodies, collider shapes, compound shapes, impulses, kinematic motion, and ray
  casts.
- **Filament** through an Android Platform View for `.glb` rendering, model
  instances, animations, lights, environment settings, procedural meshes, and
  shader materials.

The APIs are intentionally separate. You can use only Jolt, only Filament, the
included `StageScene` component runtime, or your own scene layer.

## Features

| Capability | Current API |
| --- | --- |
| Physics worlds | Create, step, and dispose reusable `PhysicsWorld` instances |
| Rigid bodies | Static, kinematic, and dynamic bodies |
| Collider shapes | Box, capsule, sphere, cylinder, and compound colliders |
| Spatial queries | Finite Jolt ray casts with closest-hit results |
| Native rendering | Filament Android viewport |
| 3D assets | Reusable `.glb` assets and independent visual instances |
| Animations | Inspect clips and control per-instance playback |
| Lighting | Directional and movable point lights |
| Procedural meshes | Terrain, atlas textures, normals, and optional collider metadata |
| Shader materials | `.mat` / `.shader` metadata with compiled `.filamat` assets |
| Debug tools | Compact collider inspector in Flutter debug builds |

## Suitable For

- interactive product and property visualization;
- lightweight Flutter games and gameplay prototypes;
- educational physics demos;
- animated 3D model viewers;
- object picking with ray casting;
- reusable scene and interaction experiments.

## Project Status

Stage 3D is an experimental alpha. The native Jolt and Filament backend
currently targets Android. Other Flutter targets use a lightweight preview
physics backend for tests and UI iteration. Public APIs may change before a
stable `1.0.0` release.

## Quick Start

Import the public API:

```dart
import 'package:stage_3d/jolt_physics.dart';
```

Rendering prototypes have a separate entrypoint:

```dart
import 'package:stage_3d/jolt_rendering.dart';
```

Create a world, floor, and dynamic ball:

```dart
final world = createPhysicsWorld();

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
    transform: PhysicsTransform(position: Vector3(0, 4, 0)),
  ),
);

world.addImpulse(ball, const Vector3(2, 4, 0));
world.step(1 / 60);

final transform = world.getTransform(ball);

world.destroyBody(ball);
world.destroyBody(floor);
world.dispose();
```

## Scene Node Example

Use `StageObject.node` when one object needs a shared transform for rendering,
physics, input, scripts, or other behavior. This is similar to a Godot node with
components attached to it.

The components are regular Dart objects. Applications can attach
`PhysicsBodyComponent`, `RenderModelComponent`, `PositionedModel`, or custom
`StageComponent` subclasses to their own scene objects instead of using the
included demo scene.

```dart
import 'package:stage_3d/jolt_physics.dart';
import 'package:stage_3d/jolt_rendering.dart';

final world = createPhysicsWorld();
final scene = StageScene();
final models = RenderModelController();

final foxAsset = models.loadAsset(
  const ModelAsset(assetPath: 'models/Fox.glb', animationIndex: 0),
);

final foxTransform = const PhysicsTransform(
  position: Vector3(0, 5, 0),
);

final fox = scene.add(
  StageObject.node(
    'fox',
    transform: foxTransform,
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
          transform: foxTransform,
        ),
      ),
      PositionedModel(
        asset: foxAsset,
        position: Vector3(0, 0.2, 0),
      ).toComponent(models),
    ],
  ),
);

void tick(double deltaSeconds) {
  world.step(deltaSeconds);
  scene.update(deltaSeconds);
}
```

`CompoundShape` groups multiple local `PositionedShape` colliders into one Jolt
body. `PositionedModel` adds a local visual offset to the same node, so the
model and collider move together while still being tuned independently.

## Resource Lifetime

Stage 3D uses native C++ resources through Jolt and Filament. Dart garbage
collection does not automatically free every native renderer or physics object,
so applications should keep ownership explicit.

Recommended lifecycle:

```dart
final world = createPhysicsWorld();
final scene = StageScene();
final models = RenderModelController();
final lights = RenderLightController();

final asset = models.loadAsset(
  const ModelAsset(assetPath: 'models/Fox.glb'),
);
final instance = models.createInstance(
  asset,
  transform: const PhysicsTransform(position: Vector3(0, 0, 0)),
);
final light = lights.createLight(
  const DirectionalLight(direction: Vector3(0, -1, -0.25)),
);

// When removing individual objects created manually:
models.destroyInstance(instance);
lights.destroyLight(light);

// When closing the scene/screen:
scene.dispose();
world.dispose();
```

If a model is attached through `RenderModelComponent`, disposing its
`StageObject` or the whole `StageScene` destroys that visible instance for you.
The bundled `FilamentViewport` also releases native Filament assets, procedural
meshes, lights, materials, textures, skybox, and renderer objects when the
Flutter platform view is disposed.

For long-running apps, avoid repeatedly creating new model instances, lights, or
procedural meshes without destroying the old ones. Reuse loaded assets and
instances when possible, and unload whole screens/scenes by calling
`StageScene.dispose()` and `PhysicsWorld.dispose()`.

## Documentation

- [Physics API guide](doc/physics_api.md)
- [Rendering bridge](doc/rendering_bridge.md)
- [Rendering lights](doc/rendering_lights.md)
- [Rendering meshes and shaders](doc/rendering_meshes.md)
- [Stage scene runtime](doc/stage_scene.md)
- [Virtual joystick](doc/virtual_joystick.md)
- Public Dart entrypoint: [`lib/jolt_physics.dart`](lib/jolt_physics.dart)
- Rendering entrypoint: [`lib/jolt_rendering.dart`](lib/jolt_rendering.dart)
- Collider prototypes: [`lib/physics/collider_shape.dart`](lib/physics/collider_shape.dart)
- Rigid body prototypes: [`lib/physics/rigid_body.dart`](lib/physics/rigid_body.dart)
- Light prototypes: [`lib/rendering/light.dart`](lib/rendering/light.dart)
- Model asset prototypes: [`lib/rendering/model_asset.dart`](lib/rendering/model_asset.dart)
- Mesh prototypes: [`lib/rendering/textured_mesh_prototype.dart`](lib/rendering/textured_mesh_prototype.dart)

## Architecture

```text
Flutter application
        |
        | Dart API
        v
PhysicsWorld and RigidBody
        |
        | dart:ffi
        v
Jolt Physics C++ adapter
```

The included Android demo adds an independent rendering path:

```text
Jolt body transform -> Flutter scene -> MethodChannel -> Filament -> Fox.glb
```

Jolt calculates physics. Filament renders the visual model. The two systems are
kept separate so a visual model can use the collider that best fits gameplay.

Procedural mesh prototypes currently serialize from Dart into the Android
Filament bridge as temporary GLB assets. They support generated planes,
heightmapped terrain, atlas texture crops, recalculated normals, basic PBR
settings, optional collider metadata, and custom Filament shader materials.
Dart can describe `.mat` / `.shader` sources, compiled `.filamat` assets,
scalar uniforms, color uniforms, and named texture uniforms such as normal or
roughness maps.

## Run The Demo

```sh
flutter run
```

The demo supports orbit gestures, pinch zoom, pause, model reset, and view
reset. Its directional light and movable blue point light are both created from
Dart prototypes; the point light follows the Jolt body every frame. Debug
builds also show a compact top-down collider map with `BodyId` labels.

## Current Platform Support

| Platform | Backend |
| --- | --- |
| Android | Jolt Physics through `dart:ffi` |
| Other Flutter targets | Lightweight preview backend |

The current public shape API supports `BoxShape`, `CapsuleShape`,
`SphereShape`, `CylinderShape`, and `CompoundShape`.

## Native Files

- Jolt C++ adapter:
  [`android/src/main/cpp/jolt_ffi.cpp`](android/src/main/cpp/jolt_ffi.cpp)
- Filament Platform View:
  [`android/src/main/kotlin/com/stage3d/stage_3d/FilamentPlatformView.kt`](android/src/main/kotlin/com/stage3d/stage_3d/FilamentPlatformView.kt)

## Test Model

The animated `Fox.glb` asset comes from the
[Khronos glTF Sample Models repository](https://github.com/KhronosGroup/glTF-Sample-Models/tree/master/2.0/Fox).
The mesh is CC0. Rigging and animation are licensed under CC-BY 4.0 by
[@tomkranis](https://sketchfab.com/models/371dea88d7e04a76af5763f2a36866bc).
