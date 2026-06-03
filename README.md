# rtmpstreamer

Modern Flutter RTMP streaming plugin for Android and iOS.

Support & Contact: [efimovi420@gmail.com](mailto:efimovi420@gmail.com)

If this package helps your project, please consider starring the repository.

# Stage 3D

**Stage 3D is a Flutter runtime for prototyping interactive 3D scenes with
native rendering, physics, animations, lighting, and spatial queries.**

Use Stage 3D when a Flutter application or game needs reusable native 3D
building blocks without embedding scene logic directly in UI widgets.

Stage 3D currently combines
[Jolt Physics](https://github.com/jrouwe/JoltPhysics) `v5.5.0` with
[Filament](https://github.com/google/filament) rendering on Android.

## Features

| Capability | Current API |
| --- | --- |
| Physics worlds | Create, step, and dispose reusable `PhysicsWorld` instances |
| Rigid bodies | Static, kinematic, and dynamic bodies |
| Collider shapes | Box, capsule, sphere, and cylinder |
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

Stage 3D is an early prototype. The native Jolt and Filament backend currently
targets Android. Other Flutter targets use a lightweight preview physics
backend for tests and UI iteration.

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

## Documentation

- [Physics API guide](doc/physics_api.md)
- [Rendering lights](doc/rendering_lights.md)
- [Rendering meshes and shaders](doc/rendering_meshes.md)
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
settings, optional collider metadata, and shader material metadata. Compiled
`.filamat` shader assets can be described from Dart; applying custom
`.filamat` materials inside the Android renderer is the next integration step.

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
`SphereShape`, and `CylinderShape`.

## Native Files

- Jolt C++ adapter:
  [`android/app/src/main/cpp/jolt_ffi.cpp`](android/app/src/main/cpp/jolt_ffi.cpp)
- Filament Platform View:
  [`android/app/src/main/kotlin/com/example/jolt_physics_dart/FilamentPlatformView.kt`](android/app/src/main/kotlin/com/example/jolt_physics_dart/FilamentPlatformView.kt)

## Test Model

The animated `Fox.glb` asset comes from the
[Khronos glTF Sample Models repository](https://github.com/KhronosGroup/glTF-Sample-Models/tree/master/2.0/Fox).
The mesh is CC0. Rigging and animation are licensed under CC-BY 4.0 by
[@tomkranis](https://sketchfab.com/models/371dea88d7e04a76af5763f2a36866bc).
