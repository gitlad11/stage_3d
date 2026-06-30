# Changelog

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
