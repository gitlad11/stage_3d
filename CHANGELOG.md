# Changelog

## 0.1.0-beta.2

- Fixed Android release APK packaging for the demo app by preserving Flutter's
  generated Dart AOT `libapp.so` in native library merges.
- Reduced Android texture upload memory usage by downscaling large mesh texture
  assets and avoiding repeated bitmap tiling for texture repeats.
- Added runtime mesh creation helpers on `FilamentViewportController` and
  improved orbit camera fly movement for interactive 3D scenes.
- Updated the grass card wind material so anchored blades bend from the top.

## 0.1.0-beta.1

- Fixed package ignore rules so root build output is excluded without excluding
  required nested native build files.
- Kept required Jolt `Build` CMake files in the pub.dev package archive.

## 0.1.0-alpha.4

- Fixed pub.dev packaging for Android builds by including the required
  `third_party/JoltPhysics/Build` CMake files.
- Clarified Windows backend packaging status and setup notes.

## 0.1.0-alpha.2

- Initial experimental Stage 3D release.
- Added reusable Jolt physics worlds, rigid bodies, collider shapes, compound
  colliders, and ray casting queries.
- Added Filament rendering prototypes for GLB models, independent instances,
  per-instance animation playback, lights, procedural meshes, and shader
  material metadata.
- Added `StageScene`, `StageObject.node`, and component-based physics/rendering
  synchronization.
- Added Android demo docs, resource lifetime guidance, and debug collider
  inspector notes.
