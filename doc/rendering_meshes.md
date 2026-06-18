# Rendering Meshes and Shaders

Stage 3D has an early procedural mesh prototype for Filament scenes. It is
intended for floors, simple terrain, and experiments before a full asset
pipeline is added.

## Mesh Prototype

Use `TexturedMeshPrototype` from `package:stage_3d/jolt_rendering.dart`.

```dart
final mesh = TexturedMeshPrototype.terrain(
  width: 4,
  depth: 2.5,
  heightMap: MeshHeightMap.wave(
    columns: 18,
    rows: 14,
    heightScale: 0.35,
  ),
  texture: grassAtlasTexture,
);
```

The mesh stores:

- vertices with `position`, `normal`, and `uv`;
- triangle `indices`;
- material settings;
- optional collider metadata.

On Android, the current native bridge converts this mesh into an in-memory GLB
and loads it through Filament `gltfio`.

## Textures and Atlases

Textures can be generated checker patterns or Android asset PNGs.

```dart
const grassAtlasTexture = MeshTexturePrototype.asset(
  assetPath: 'textures/grass_pbr_atlas.png',
  sourceRegion: MeshTextureRegion(
    left: 7 / 1536,
    top: 50 / 1024,
    right: 372 / 1536,
    bottom: 424 / 1024,
  ),
  repeatU: 2,
  repeatV: 2,
);
```

`sourceRegion` lets one PNG atlas contain multiple maps or material tiles. The
current demo crops the grass albedo region from the atlas and tiles it over the
terrain mesh.

## Heightmaps and Normals

`TexturedMeshPrototype.terrain` creates a grid from height samples.

```dart
final heightMap = MeshHeightMap.samples(
  columns: 3,
  rows: 3,
  values: [0, 0.5, 0, 0.5, 1, 0.5, 0, 0.5, 0],
  heightScale: 2,
);
```

Normals are recalculated from the generated triangles by default:

```dart
normalMode: MeshNormalMode.recalculate
```

This is enough for a visual terrain prototype. Matching Jolt terrain physics
will need `HeightFieldShape` or `MeshShape` support in the FFI layer.

## Optional Colliders

Meshes can carry optional collider metadata:

```dart
collider: const MeshColliderPrototype.staticBox(
  physics.BoxShape(halfWidth: 8, halfHeight: 0.25, halfDepth: 8),
)
```

Supported metadata:

- `disabled()` for visual-only meshes;
- `staticBox(...)` for a Jolt box collider that the current FFI can create;
- `meshShape()` as a future hook for Jolt triangle mesh collision.

The renderer does not create physics bodies. Scene code should decide whether
to read `mesh.collider` and create matching Jolt bodies.

## Shader Materials

Filament material source files are authored as `.mat`. This project also allows
`.shader` as a source alias in Dart metadata. Android Filament runtime loads a
compiled `.filamat`, and the Android Gradle build can generate that file from
the source material.

```text
grass_wind.mat -> matc -> grass_wind.filamat
```

The demo includes:

- `android/app/src/main/assets/materials/grass_wind.mat`
- `android/app/src/main/assets/materials/grass_wind.shader`
- `android/app/src/main/assets/materials/grass_wind.filamat`

Use it from Dart:

```dart
final material = MeshMaterialPrototype.shaderSource(
  shaderAssetPath: 'materials/grass_wind.shader',
  texture: grassAtlasTexture,
  uniforms: [
    MaterialShaderUniform.float('windStrength', 0.18),
    MaterialShaderUniform.float('windScale', 3),
    MaterialShaderUniform.color('tint', const Color(0xffd9f99d)),
  ],
);
```

`shaderSource` derives `materials/grass_wind.filamat` automatically. If a
project already has a compiled file, it can point to it directly:

```dart
final material = MeshMaterialPrototype.filamat(
  assetPath: 'materials/grass_wind.filamat',
  texture: grassAtlasTexture,
);
```

Current status: shader metadata is serialized to the native bridge. Android
loads the compiled `.filamat`, creates a Filament material instance, and applies
it to the procedural mesh at runtime.

## Custom Shader Textures

Custom materials can receive one main texture through `texture`. The Android
renderer binds that texture to a sampler named `albedo`.

```dart
final material = MeshMaterialPrototype.shaderSource(
  shaderAssetPath: 'materials/my_water.shader',
  texture: albedoTexture,
);
```

Shaders that need more maps can use named texture uniforms. This is useful for
PBR atlases where albedo, normal, and roughness live in different regions of
one PNG.

```dart
const waterAlbedo = MeshTexturePrototype.asset(
  assetPath: 'textures/water_ocean_pbr_atlas.png',
  sourceRegion: MeshTextureRegion.pixels(
    imageWidth: 1254,
    imageHeight: 1254,
    x: 3,
    y: 68,
    width: 311,
    height: 309,
  ),
);

const waterNormal = MeshTexturePrototype.asset(
  assetPath: 'textures/water_ocean_pbr_atlas.png',
  sourceRegion: MeshTextureRegion.pixels(
    imageWidth: 1254,
    imageHeight: 1254,
    x: 316,
    y: 68,
    width: 310,
    height: 309,
  ),
);

final material = MeshMaterialPrototype.shaderSource(
  shaderAssetPath: 'materials/water.shader',
  texture: waterAlbedo,
  textureUniforms: const {
    'normalMap': waterNormal,
  },
  uniforms: [
    MaterialShaderUniform.float('normalStrength', 0.5),
    MaterialShaderUniform.color('tint', const Color(0xffd7f8ff)),
  ],
);
```

The names in `textureUniforms` must match sampler parameters in the Filament
material source:

```glsl
parameters : [
    {
        type : sampler2d,
        name : albedo
    },
    {
        type : sampler2d,
        name : normalMap
    },
    {
        type : float,
        name : normalStrength
    }
]
```

The current Android backend supports:

- `.mat` and `.shader` source files in Android assets;
- build-time compilation to `.filamat`;
- direct use of precompiled `.filamat` assets;
- main `albedo` texture;
- additional named sampler textures through `textureUniforms`;
- `float`, `bool`, and `color` uniforms.

Limitations:

- material source files must be available at Android build time;
- runtime loading uses compiled `.filamat`, not raw `.mat` / `.shader`;
- iOS, desktop, and web renderers do not yet implement this Filament material
  pipeline;
- sampler and uniform names must exactly match the material source.

## Compiling Materials

The Android Gradle project has a `compileFilamentMaterials` task. It downloads
the matching Filament `matc` compiler from Maven for the current host, then
scans `android/app/src/main/assets/materials` for `.mat` and `.shader` files and
writes matching `.filamat` files before Android asset merging.

```powershell
cd android
.\gradlew.bat :app:compileFilamentMaterials
```

Supported `matc` hosts for Filament `1.71.5` are Windows x86_64, Linux x86_64,
and macOS Apple Silicon. Keep `.mat` or `.shader` files as readable source
files. Runtime loading still uses the compiled `.filamat` files.
