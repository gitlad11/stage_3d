# Rendering Bridge

Stage 3D separates scene prototypes from the renderer backend. Dart classes such
as `ModelAsset`, `TexturedMeshPrototype`, `MeshMaterialPrototype`, and `Light`
describe what should exist in a scene. A `RenderSceneBridge` decides how those
descriptions are sent to a concrete renderer.

The bundled Android viewport uses:

```text
RenderModelController / RenderLightController
        |
        v
MethodChannelRenderSceneBridge
        |
        v
FilamentPlatformView.kt
```

Applications can keep the same Dart controllers and implement their own bridge
for a custom Kotlin Filament renderer.

```dart
final models = RenderModelController();
final lights = RenderLightController();

models.attachBridge(myCustomBridge);
lights.attachBridge(myCustomBridge);

final roomAsset = models.loadAsset(
  const ModelAsset(assetPath: 'models/room.glb'),
);

models.createInstance(
  roomAsset,
  transform: const PhysicsTransform(position: Vector3(0, 0, -4)),
);

lights.createLight(
  const DirectionalLight(direction: Vector3(0, -1, -0.25)),
);
```

`MethodChannelRenderSceneBridge` is still available for the built-in Android
Filament viewport. A custom bridge can reuse the same method names or map the
operations to a different native renderer.
