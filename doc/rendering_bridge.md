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

## Resource Lifetime

Filament owns native GPU and CPU resources outside the Dart heap. Dart garbage
collection does not automatically release those native objects. The application
or scene layer should decide who owns each render object and destroy it when it
is no longer needed.

Use these rules:

- `RenderModelController.loadAsset(...)` registers a reusable GLB asset.
- `RenderModelController.createInstance(...)` creates one visible instance of
  that asset.
- `RenderModelController.destroyInstance(...)` removes a visible instance from
  Dart and the renderer.
- `RenderLightController.destroyLight(...)` removes a native light.
- `RenderModelController.detach()` and `RenderLightController.detach()` only
  disconnect Dart from the current viewport; they keep Dart-side prototypes so
  they can be recreated when another bridge attaches.
- `FilamentViewport.dispose()` releases the bundled Android viewport and its
  native Filament resources.

If a model is attached with `RenderModelComponent`, the component calls
`destroyInstance` from `onDetach()`. Disposing a `StageObject` or `StageScene`
therefore cleans up those component-owned visible instances.

```dart
final scene = StageScene();
final models = RenderModelController();

final asset = models.loadAsset(
  const ModelAsset(assetPath: 'models/chair.glb'),
);

final instance = models.createInstance(
  asset,
  transform: const PhysicsTransform(position: Vector3(0, 0, 0)),
);

// Later, when this visible chair is no longer part of the scene:
models.destroyInstance(instance);

// Later, when the whole scene is closed:
scene.dispose();
```

The current built-in viewport unloads registered GLB assets when the platform
view itself is disposed. It does not yet expose a public Dart `unloadAsset`
method for removing one loaded asset while keeping the same viewport alive.
Long-running apps should reuse loaded assets and destroy unused instances
instead of repeatedly loading the same GLB under new asset ids.
