import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:stage_3d/physics/collider_shape.dart' as physics;
import 'package:stage_3d/stage_3d.dart';

void main() {
  test('ModelAsset serializes GLB renderer settings', () {
    const asset = ModelAsset(
      assetPath: 'models/room.glb',
      normalizedScale: 2,
      animationIndex: 1,
    );

    expect(asset.toMessage(), {
      'assetPath': 'models/room.glb',
      'normalizedScale': 2,
      'animationIndex': 1,
      'verticalAnchor': 'center',
    });
  });

  test('ModelAsset can point at an OBJ renderer asset', () {
    const asset = ModelAsset(assetPath: 'models/chair.obj');

    expect(asset.toMessage(), {
      'assetPath': 'models/chair.obj',
      'normalizedScale': 1,
      'animationIndex': null,
      'verticalAnchor': 'center',
    });
  });

  test('ModelAsset serializes vertical anchor', () {
    const asset = ModelAsset(
      assetPath: 'models/tree.glb',
      verticalAnchor: ModelVerticalAnchor.bottom,
    );

    expect(asset.toMessage(), {
      'assetPath': 'models/tree.glb',
      'normalizedScale': 1,
      'animationIndex': null,
      'verticalAnchor': 'bottom',
    });
  });

  test('RenderModelController retains the latest instance transform', () {
    final models = RenderModelController();
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/room.glb'),
    );
    final instance = models.createInstance(
      asset,
      transform: const PhysicsTransform(position: Vector3(1, 0, 2)),
    );

    const updated = PhysicsTransform(position: Vector3(3, 0, 4));
    models.setTransform(instance, updated);

    expect(instance.transform, same(updated));
  });

  test(
    'RenderModelController requires instances to be destroyed before unload',
    () {
      final models = RenderModelController();
      final asset = models.loadAsset(
        const ModelAsset(assetPath: 'models/room.glb'),
      );
      final instance = models.createInstance(
        asset,
        transform: const PhysicsTransform(position: Vector3.zero),
      );

      expect(() => models.unloadAsset(asset), throwsStateError);

      models.destroyInstance(instance);
      expect(() => models.unloadAsset(asset), returnsNormally);
    },
  );

  test('ModelAnimation reads native clip metadata', () {
    final animation = ModelAnimation.fromMessage({
      'index': 2,
      'name': 'Walk',
      'durationSeconds': 1.5,
    });

    expect(animation.index, 2);
    expect(animation.name, 'Walk');
    expect(animation.durationSeconds, 1.5);
  });

  test('RenderModelController retains animation playback state', () {
    final models = RenderModelController();
    final asset = models.loadAsset(
      const ModelAsset(assetPath: 'models/character.glb'),
    );
    final instance = models.createInstance(
      asset,
      transform: const PhysicsTransform(position: Vector3.zero),
    );

    models.playAnimation(instance, animationIndex: 1, speed: 1.5);
    expect(instance.animation?.animationIndex, 1);
    expect(instance.animation?.speed, 1.5);

    models.pauseAnimation(instance);
    expect(instance.animation?.paused, isTrue);

    models.resumeAnimation(instance);
    expect(instance.animation?.paused, isFalse);

    models.stopAnimation(instance);
    expect(instance.animation, isNull);
  });

  test('TexturedMeshPrototype creates a UV mapped plane', () {
    final mesh = TexturedMeshPrototype.plane(
      width: 4,
      depth: 2,
      texture: const MeshTexturePrototype(
        primaryColor: Color(0xff14b8a6),
        secondaryColor: Color(0xfff8fafc),
        repeatU: 8,
        repeatV: 4,
      ),
    );

    expect(mesh.vertices, hasLength(45));
    expect(mesh.indices, hasLength(192));
    expect(mesh.indices.take(6), [0, 10, 1, 0, 9, 10]);
    expect(mesh.vertices.first.position.x, -2);
    expect(mesh.vertices.first.normal.y, 1);
    expect(mesh.vertices.first.uv.dx, 0);
    expect(mesh.toMessage()['texture'], {
      'kind': 'checker',
      'primaryColor': const Color(0xff14b8a6).toARGB32(),
      'secondaryColor': const Color(0xfff8fafc).toARGB32(),
      'repeatU': 8.0,
      'repeatV': 4.0,
    });
  });

  test('MeshMaterialPrototype serializes Filament mat source paths', () {
    final material = MeshMaterialPrototype.filamentSource(
      matAssetPath: 'material_sources/terrain.mat',
      filamatAssetPath: 'materials/terrain.filamat',
      baseColor: const Color(0xffa7f3d0),
      roughnessFactor: 0.7,
      doubleSided: false,
    );

    expect(material.toMessage(), {
      'kind': 'filamentSource',
      'baseColor': const Color(0xffa7f3d0).toARGB32(),
      'metallicFactor': 0,
      'roughnessFactor': 0.7,
      'doubleSided': false,
      'shader': {
        'sourceAssetPath': 'material_sources/terrain.mat',
        'filamatAssetPath': 'materials/terrain.filamat',
        'uniforms': [],
      },
      'matAssetPath': 'material_sources/terrain.mat',
      'filamatAssetPath': 'materials/terrain.filamat',
    });
  });

  test('MeshMaterialPrototype serializes custom shader source paths', () {
    final material = MeshMaterialPrototype.shaderSource(
      shaderAssetPath: 'material_sources/grass_wind.shader',
      filamatAssetPath: 'materials/grass_wind.filamat',
      uniforms: [
        MaterialShaderUniform.float('windStrength', 0.25),
        MaterialShaderUniform.float('windScale', 3),
        MaterialShaderUniform.bool('receiveWind', true),
        MaterialShaderUniform.color('tint', const Color(0xff86efac)),
      ],
    );

    expect(material.toMessage(), {
      'kind': 'shader',
      'baseColor': Colors.white.toARGB32(),
      'metallicFactor': 0,
      'roughnessFactor': 0.85,
      'doubleSided': true,
      'shader': {
        'sourceAssetPath': 'material_sources/grass_wind.shader',
        'filamatAssetPath': 'materials/grass_wind.filamat',
        'uniforms': [
          {'name': 'windStrength', 'type': 'float', 'value': 0.25},
          {'name': 'windScale', 'type': 'float', 'value': 3.0},
          {'name': 'receiveWind', 'type': 'bool', 'value': true},
          {
            'name': 'tint',
            'type': 'color',
            'value': const Color(0xff86efac).toARGB32(),
          },
        ],
      },
      'filamatAssetPath': 'materials/grass_wind.filamat',
    });
  });

  test('MeshMaterialPrototype serializes named texture uniforms', () {
    const normalTexture = MeshTexturePrototype.asset(
      assetPath: 'textures/water_ocean_pbr_atlas.png',
      sourceRegion: MeshTextureRegion(
        left: 316 / 1254,
        top: 68 / 1254,
        right: 626 / 1254,
        bottom: 377 / 1254,
      ),
    );
    final material = MeshMaterialPrototype.shaderSource(
      shaderAssetPath: 'material_sources/water.shader',
      filamatAssetPath: 'materials/water.filamat',
      textureUniforms: const {'normalMap': normalTexture},
    );

    expect(material.toMessage()['textureUniforms'], {
      'normalMap': {
        'kind': 'asset',
        'primaryColor': const Color(0xff14b8a6).toARGB32(),
        'secondaryColor': const Color(0xfff8fafc).toARGB32(),
        'repeatU': 1.0,
        'repeatV': 1.0,
        'assetPath': 'textures/water_ocean_pbr_atlas.png',
        'sourceRegion': {
          'left': 316 / 1254,
          'top': 68 / 1254,
          'right': 626 / 1254,
          'bottom': 377 / 1254,
        },
      },
    });
  });

  test('MeshMaterialPrototype can use an already compiled filamat asset', () {
    final material = MeshMaterialPrototype.filamat(
      assetPath: 'materials/water.filamat',
      uniforms: [MaterialShaderUniform.float('waveStrength', 0.4)],
    );

    expect(material.toMessage(), {
      'kind': 'shader',
      'baseColor': Colors.white.toARGB32(),
      'metallicFactor': 0,
      'roughnessFactor': 0.85,
      'doubleSided': true,
      'shader': {
        'filamatAssetPath': 'materials/water.filamat',
        'uniforms': [
          {'name': 'waveStrength', 'type': 'float', 'value': 0.4},
        ],
      },
      'filamatAssetPath': 'materials/water.filamat',
    });
  });

  test('MeshTexturePrototype serializes atlas asset region', () {
    const texture = MeshTexturePrototype.asset(
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

    expect(texture.toMessage(), {
      'kind': 'asset',
      'primaryColor': const Color(0xff14b8a6).toARGB32(),
      'secondaryColor': const Color(0xfff8fafc).toARGB32(),
      'repeatU': 2,
      'repeatV': 2,
      'assetPath': 'textures/grass_pbr_atlas.png',
      'sourceRegion': {
        'left': 7 / 1536,
        'top': 50 / 1024,
        'right': 372 / 1536,
        'bottom': 424 / 1024,
      },
    });
  });

  test('TexturedMeshPrototype terrain builds heightmapped normals', () {
    final heightMap = MeshHeightMap.samples(
      columns: 3,
      rows: 3,
      values: [0, 0.5, 0, 0.5, 1, 0.5, 0, 0.5, 0],
      heightScale: 2,
    );
    final mesh = TexturedMeshPrototype.terrain(
      width: 2,
      depth: 2,
      heightMap: heightMap,
    );

    expect(mesh.vertices, hasLength(9));
    expect(mesh.indices, hasLength(24));
    expect(mesh.vertices[4].position.y, 2);
    expect(mesh.vertices[4].normal.y, greaterThan(0));
    expect(mesh.vertices[1].normal.y, greaterThan(0));
    expect(mesh.vertices[1].normal.y, lessThan(1));
  });

  test('TexturedMeshPrototype can carry an optional collider prototype', () {
    final mesh = TexturedMeshPrototype.plane(
      width: 8,
      depth: 8,
      collider: const MeshColliderPrototype.staticBox(
        physics.BoxShape(halfWidth: 4, halfHeight: 0.1, halfDepth: 4),
      ),
    );

    expect(mesh.collider.enabled, isTrue);
    expect(mesh.collider.kind, MeshColliderKind.staticBox);
    expect(mesh.toMessage()['collider'], {
      'enabled': true,
      'kind': 'staticBox',
      'staticBox': {'halfWidth': 4.0, 'halfHeight': 0.1, 'halfDepth': 4.0},
    });
  });
}
