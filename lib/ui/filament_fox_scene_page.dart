import 'package:flutter/material.dart';

import '../physics/physics_transform.dart';
import '../physics/vector3.dart';
import '../rendering/environment.dart';
import '../rendering/filament_viewport.dart';
import '../rendering/light.dart';
import '../rendering/model_asset.dart';
import '../rendering/render_environment_controller.dart';
import '../rendering/render_light_controller.dart';
import '../rendering/render_model_controller.dart';
import '../rendering/render_options.dart';
import '../rendering/render_options_controller.dart';
import '../rendering/stage_camera.dart';
import '../rendering/textured_mesh_prototype.dart';
import '../scene/orbit_camera.dart';

class FilamentFoxScenePage extends StatefulWidget {
  const FilamentFoxScenePage({super.key});

  @override
  State<FilamentFoxScenePage> createState() => _FilamentFoxScenePageState();
}

class _FilamentFoxScenePageState extends State<FilamentFoxScenePage> {
  late final OrbitCamera _fallbackCamera;
  late final FilamentViewportController _viewportController;
  late final RenderEnvironmentController _environmentController;
  late final RenderOptionsController _optionsController;
  late final RenderLightController _lightController;
  late final RenderModelController _modelController;
  late final RenderModelInstance _foxInstance;
  late final TexturedMeshPrototype _groundMesh;

  var _status = 'Loading Fox.glb, TreePack.obj, and mighty_oak_trees.glb';

  @override
  void initState() {
    super.initState();
    _fallbackCamera = OrbitCamera();
    _viewportController = FilamentViewportController()
      ..setCamera(
        const StageCamera.orbit(
          target: Vector3(0, 0.65, 0),
          yaw: -0.55,
          pitch: 0.28,
          distance: 4.6,
        ),
      );
    _environmentController = RenderEnvironmentController(
      initialEnvironment: const RenderEnvironment(
        skyColor: Vector3(0.035, 0.045, 0.055),
        ambientIntensity: 52000,
        reflectionIntensity: 0.85,
      ),
    );
    _optionsController = RenderOptionsController(
      initialOptions: const RenderOptions(
        shadows: true,
        shadowType: ShadowType.dpcf,
        ambientOcclusion: AmbientOcclusionOptions(
          enabled: true,
          radius: 0.35,
          intensity: 0.55,
          power: 1.0,
          quality: RenderQuality.low,
        ),
        msaa: MsaaOptions(enabled: true, sampleCount: 2),
      ),
    );
    _lightController = RenderLightController()
      ..createLight(
        const DirectionalLight(
          direction: Vector3(-0.35, -0.85, -0.25),
          intensity: 125000,
        ),
      )
      ..createLight(
        const PointLight(
          position: Vector3(0, 2.6, 2.0),
          color: Vector3(0.55, 0.75, 1),
          intensity: 3200,
          falloffRadius: 5,
          castShadows: false,
        ),
      );
    _modelController = RenderModelController();
    _groundMesh = _createFoxGroundMesh();
    final foxAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'models/Fox.glb',
        verticalAnchor: ModelVerticalAnchor.bottom,
        normalizedScale: 1.2,
      ),
    );
    final treeAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'models/TreePack.obj',
        verticalAnchor: ModelVerticalAnchor.bottom,
        normalizedScale: 1.6,
      ),
    );
    final farTreeAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'models/TreePack.obj',
        verticalAnchor: ModelVerticalAnchor.bottom,
        normalizedScale: 1.6,
        castShadows: false,
        receiveShadows: false,
      ),
    );
    final oakAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'models/mighty_oak_trees.glb',
        verticalAnchor: ModelVerticalAnchor.bottom,
        normalizedScale: 8.8,
      ),
    );
    _foxInstance = _modelController.createInstance(
      foxAsset,
      transform: const PhysicsTransform(position: Vector3(-1.1, 0, 0)),
    );
    _modelController.createInstance(
      treeAsset,
      transform: const PhysicsTransform(position: Vector3(1.15, 0, 0)),
    );
    _createTreeLodLayout(nearAsset: oakAsset, farAsset: farTreeAsset);
  }

  Future<void> _onRendererReady() async {
    final animations = await _modelController.getAnimations(_foxInstance);
    if (!mounted) {
      return;
    }
    if (animations.isNotEmpty) {
      _modelController.playAnimation(
        _foxInstance,
        animationIndex: animations.first.index,
      );
    }
    setState(() {
      _status = animations.isEmpty
          ? 'Fox, trees, and grass blocks loaded'
          : 'Fox, trees, and grass blocks loaded, '
                '${animations.length} animations';
    });
  }

  @override
  void dispose() {
    _viewportController.detach();
    _environmentController.detach();
    _optionsController.detach();
    _lightController.detach();
    _modelController.detach();
    _fallbackCamera.dispose();
    super.dispose();
  }

  void _createTreeLodLayout({
    required RenderModelAsset nearAsset,
    required RenderModelAsset farAsset,
  }) {
    const nearTrees = [
      _TreePlacement(position: Vector3(-1.1, 0, 1.85)),
    ];
    const farTrees = [
      _TreePlacement(position: Vector3(-4.8, 0, 4.1)),
      _TreePlacement(position: Vector3(-2.4, 0, 5.35)),
      _TreePlacement(position: Vector3(0.65, 0, 5.2)),
      _TreePlacement(position: Vector3(3.55, 0, 3.95)),
      _TreePlacement(position: Vector3(5.25, 0, 1.35)),
    ];

    for (final placement in nearTrees) {
      _modelController.createInstance(
        nearAsset,
        transform: placement.transform,
      );
    }
    for (final placement in farTrees) {
      _modelController.createInstance(
        farAsset,
        transform: placement.transform,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FilamentViewport(
            cube: const PhysicsTransform(position: Vector3.zero),
            fallbackCamera: _fallbackCamera,
            controller: _viewportController,
            environmentController: _environmentController,
            optionsController: _optionsController,
            lightController: _lightController,
            modelController: _modelController,
            meshPrototypes: [_groundMesh],
            showFallbackPreview: false,
            onRendererReady: _onRendererReady,
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xcc05070a),
                    border: Border.all(color: const Color(0x5538bdf8)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Text(
                      _status,
                      style: const TextStyle(
                        color: Color(0xffdbeafe),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _TreePlacement {
  const _TreePlacement({
    required this.position,
  });

  final Vector3 position;

  PhysicsTransform get transform => PhysicsTransform(position: position);
}

TexturedMeshPrototype _createFoxGroundMesh() {
  const texture = MeshTexturePrototype.asset(
    assetPath: 'textures/grass_pbr_atlas.png',
    sourceRegion: MeshTextureRegion(
      left: 7 / 1536,
      top: 50 / 1024,
      right: 372 / 1536,
      bottom: 424 / 1024,
    ),
    repeatU: 6,
    repeatV: 6,
  );
  final material = MeshMaterialPrototype.filamat(
    assetPath: 'materials/grass_wind.filamat',
    texture: texture,
    roughnessFactor: 0.95,
    doubleSided: true,
  );
  const tileSize = 5.0;
  const tileCount = 3;
  const halfWidth = tileSize * tileCount / 2;
  const halfDepth = tileSize * tileCount / 2;
  const top = 0.0;
  const bottom = -0.16;
  final vertices = <MeshVertex>[];
  final indices = <int>[];

  void addQuad({
    required Vector3 normal,
    required Vector3 a,
    required Vector3 b,
    required Vector3 c,
    required Vector3 d,
    double uvRepeat = 6,
  }) {
    final start = vertices.length;
    vertices.addAll(
      _groundQuad(normal: normal, a: a, b: b, c: c, d: d, uvRepeat: uvRepeat),
    );
    indices.addAll([start, start + 2, start + 1, start, start + 3, start + 2]);
  }

  for (var row = 0; row < tileCount; row++) {
    for (var column = 0; column < tileCount; column++) {
      final left = -halfWidth + column * tileSize;
      final right = left + tileSize;
      final back = -halfDepth + row * tileSize;
      final front = back + tileSize;
      addQuad(
        normal: const Vector3(0, 1, 0),
        a: Vector3(left, top, back),
        b: Vector3(right, top, back),
        c: Vector3(right, top, front),
        d: Vector3(left, top, front),
      );
    }
  }

  addQuad(
    normal: const Vector3(0, -1, 0),
    a: const Vector3(-halfWidth, bottom, halfDepth),
    b: const Vector3(halfWidth, bottom, halfDepth),
    c: const Vector3(halfWidth, bottom, -halfDepth),
    d: const Vector3(-halfWidth, bottom, -halfDepth),
    uvRepeat: tileCount * 6,
  );
  addQuad(
    normal: const Vector3(0, 0, 1),
    a: const Vector3(-halfWidth, bottom, halfDepth),
    b: const Vector3(-halfWidth, top, halfDepth),
    c: const Vector3(halfWidth, top, halfDepth),
    d: const Vector3(halfWidth, bottom, halfDepth),
    uvRepeat: tileCount * 6,
  );
  addQuad(
    normal: const Vector3(0, 0, -1),
    a: const Vector3(halfWidth, bottom, -halfDepth),
    b: const Vector3(halfWidth, top, -halfDepth),
    c: const Vector3(-halfWidth, top, -halfDepth),
    d: const Vector3(-halfWidth, bottom, -halfDepth),
    uvRepeat: tileCount * 6,
  );
  addQuad(
    normal: const Vector3(1, 0, 0),
    a: const Vector3(halfWidth, bottom, halfDepth),
    b: const Vector3(halfWidth, top, halfDepth),
    c: const Vector3(halfWidth, top, -halfDepth),
    d: const Vector3(halfWidth, bottom, -halfDepth),
    uvRepeat: tileCount * 6,
  );
  addQuad(
    normal: const Vector3(-1, 0, 0),
    a: const Vector3(-halfWidth, bottom, -halfDepth),
    b: const Vector3(-halfWidth, top, -halfDepth),
    c: const Vector3(-halfWidth, top, halfDepth),
    d: const Vector3(-halfWidth, bottom, halfDepth),
    uvRepeat: tileCount * 6,
  );
  return TexturedMeshPrototype(
    vertices: vertices,
    indices: indices,
    material: material,
  );
}

List<MeshVertex> _groundQuad({
  required Vector3 normal,
  required Vector3 a,
  required Vector3 b,
  required Vector3 c,
  required Vector3 d,
  double uvRepeat = 6,
}) {
  return [
    MeshVertex(position: a, normal: normal, uv: Offset.zero),
    MeshVertex(position: b, normal: normal, uv: Offset(uvRepeat, 0)),
    MeshVertex(position: c, normal: normal, uv: Offset(uvRepeat, uvRepeat)),
    MeshVertex(position: d, normal: normal, uv: Offset(0, uvRepeat)),
  ];
}
