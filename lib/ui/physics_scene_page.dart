import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../input/virtual_joystick.dart';
import '../jolt_physics.dart';
import '../rendering/filament_viewport.dart';
import '../rendering/environment.dart';
import '../rendering/light.dart';
import '../rendering/render_environment_controller.dart';
import '../rendering/model_asset.dart';
import '../rendering/physics_debug_overlay.dart';
import '../rendering/render_light_controller.dart';
import '../rendering/render_model_controller.dart';
import '../rendering/textured_mesh_prototype.dart';
import '../scene/camera_move_prototype.dart';
import '../scene/orbit_camera.dart';
import '../scene/physics_scene.dart';
import '../scene/render_model_component.dart';

class PhysicsScenePage extends StatefulWidget {
  const PhysicsScenePage({super.key});

  @override
  State<PhysicsScenePage> createState() => _PhysicsScenePageState();
}

class _PhysicsScenePageState extends State<PhysicsScenePage>
    with SingleTickerProviderStateMixin {
  late final PhysicsScene _scene;
  late final OrbitCamera _camera;
  late final VirtualJoystickController _orbitJoystick;
  late final VirtualJoystickController _moveJoystick;
  late final CameraMovePrototype _cameraMovePrototype;
  late final Ticker _ticker;
  late final FilamentViewportController _viewportController;
  late final RenderEnvironmentController _environmentController;
  late final RenderLightController _lightController;
  late final RenderLight _modelLight;
  late final RenderModelController _modelController;
  late final RenderModelComponent _foxModel;
  late final List<TexturedMeshPrototype> _groundMeshPrototypes;
  var _animations = const <ModelAnimation>[];
  var _selectedAnimationIndex = 0;
  var _animationStatus = 'Waiting for renderer';
  var _showInspector = false;
  var _showColliders = false;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _scene = PhysicsScene()..addListener(_refresh);
    _camera = OrbitCamera()..addListener(_refresh);
    _orbitJoystick = VirtualJoystickController();
    _moveJoystick = VirtualJoystickController();
    _cameraMovePrototype = const CameraMovePrototype();
    _viewportController = FilamentViewportController();
    _environmentController = RenderEnvironmentController(
      initialEnvironment: const RenderEnvironment(
        skyColor: Vector3(0.44, 0.78, 0.9),
        ambientIntensity: 45000,
        reflectionIntensity: 0.92,
      ),
    );
    _lightController = RenderLightController()
      ..createLight(
        const DirectionalLight(
          direction: Vector3(0, -0.5, -1),
          intensity: 120000,
        ),
      );
    _modelLight = _lightController.createLight(
      const PointLight(
        position: Vector3(0, 3, 0),
        color: Vector3(0.45, 0.7, 1),
        intensity: 3500,
        falloffRadius: 5,
        castShadows: false,
      ),
    );
    _modelController = RenderModelController();
    _groundMeshPrototypes = [_createJoltFloorBlockVisual()];
    final foxAsset = _modelController.loadAsset(
      const ModelAsset(
        assetPath: 'models/Fox.glb',
        verticalAnchor: ModelVerticalAnchor.bottom,
      ),
    );
    _foxModel = _scene.modelObject.add(
      RenderModelComponent(
        controller: _modelController,
        asset: foxAsset,
        visualOffset: const Vector3(0, 1.3, 0),
      ),
    );
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadAnimations() async {
    final animations = await _modelController.getAnimations(
      _foxModel.requireInstance,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _animations = animations;
      _animationStatus = animations.isEmpty
          ? 'No native animations'
          : '${animations.length} animation clips';
      if (animations.isNotEmpty) {
        _selectedAnimationIndex = animations.first.index;
      }
    });
  }

  void _playAnimation(ModelAnimation animation) {
    _modelController.playAnimation(
      _foxModel.requireInstance,
      animationIndex: animation.index,
    );
    setState(() {
      _selectedAnimationIndex = animation.index;
      _animationStatus =
          '${animation.name}  ${animation.durationSeconds.toStringAsFixed(2)}s';
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) {
      return;
    }
    _scene.step(
      (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond,
    );
    final deltaSeconds =
        (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond;
    final orbit = _orbitJoystick.value;
    const orbitSpeed = 0.65;
    final deltaYaw = orbit.x * orbitSpeed * deltaSeconds;
    final deltaPitch = orbit.y * orbitSpeed * deltaSeconds;
    _camera.orbitBy(deltaYaw, deltaPitch);
    _viewportController.orbitCamera(deltaYaw, deltaPitch);
    final move = _moveJoystick.value;
    _cameraMovePrototype.moveCamera(_camera, move, deltaSeconds);
    final nativeMove = _cameraMovePrototype.nativeMove(move, deltaSeconds);
    _viewportController.moveCamera(nativeMove.right, nativeMove.forward);
    final position = _scene.model.transform.position;
    _lightController.setPosition(_modelLight, position.translate(0, 1.5, 0.5));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _orbitJoystick.dispose();
    _moveJoystick.dispose();
    _camera
      ..removeListener(_refresh)
      ..dispose();
    _scene
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cube = _scene.model.transform;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerUp: (_) => _scene.castRayAtModel(),
              child: FilamentViewport(
                cube: cube,
                fallbackCamera: _camera,
                controller: _viewportController,
                environmentController: _environmentController,
                lightController: _lightController,
                modelController: _modelController,
                meshPrototypes: _groundMeshPrototypes,
                onRendererReady: _loadAnimations,
              ),
            ),
          ),
          if (kDebugMode && _showColliders)
            Positioned(
              bottom: 88,
              right: 16,
              child: PhysicsDebugOverlay(bodies: _scene.debugBodies),
            ),
          SafeArea(child: LayoutBuilder(builder: _buildOverlay)),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, BoxConstraints constraints) {
    final compact = constraints.maxWidth < 700;
    return Padding(
      padding: EdgeInsets.all(compact ? 12 : 20),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: _SceneHeader(
              touchStatus: _scene.touchStatus,
              compact: compact,
            ),
          ),
          if (_showInspector)
            Align(
              alignment: compact ? Alignment.topRight : Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(top: compact ? 78 : 0),
                child: _SceneInspector(
                  animations: _animations,
                  selectedIndex: _selectedAnimationIndex,
                  status: _animationStatus,
                  onSelect: _playAnimation,
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _SceneToolbar(
              paused: _scene.paused,
              showInspector: _showInspector,
              showColliders: _showColliders,
              onTogglePause: _scene.togglePause,
              onResetModel: _scene.resetCube,
              onResetView: () {
                _camera.reset();
                _viewportController.resetView();
              },
              onToggleInspector: () {
                setState(() => _showInspector = !_showInspector);
              },
              onToggleColliders: kDebugMode
                  ? () => setState(() => _showColliders = !_showColliders)
                  : null,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 70),
              child: VirtualJoystick(
                key: const ValueKey('move-joystick'),
                controller: _moveJoystick,
                size: compact ? 96 : 116,
                accentColor: const Color(0xff67e8f9),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 70),
              child: VirtualJoystick(
                key: const ValueKey('orbit-joystick'),
                controller: _orbitJoystick,
                size: compact ? 96 : 116,
                accentColor: const Color(0xffc4b5fd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TexturedMeshPrototype _createJoltFloorBlockVisual() {
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
  const halfWidth = 8.0;
  const halfDepth = 8.0;
  const top = 0.0;
  const bottom = -2.0;
  final material = MeshMaterialPrototype.checker(
    texture,
    roughnessFactor: 0.9,
    doubleSided: true,
  );
  final vertices = <MeshVertex>[
    ..._quad(
      normal: const Vector3(0, 1, 0),
      a: const Vector3(-halfWidth, top, -halfDepth),
      b: const Vector3(halfWidth, top, -halfDepth),
      c: const Vector3(halfWidth, top, halfDepth),
      d: const Vector3(-halfWidth, top, halfDepth),
    ),
    ..._quad(
      normal: const Vector3(0, -1, 0),
      a: const Vector3(-halfWidth, bottom, halfDepth),
      b: const Vector3(halfWidth, bottom, halfDepth),
      c: const Vector3(halfWidth, bottom, -halfDepth),
      d: const Vector3(-halfWidth, bottom, -halfDepth),
    ),
    ..._quad(
      normal: const Vector3(0, 0, 1),
      a: const Vector3(-halfWidth, bottom, halfDepth),
      b: const Vector3(-halfWidth, top, halfDepth),
      c: const Vector3(halfWidth, top, halfDepth),
      d: const Vector3(halfWidth, bottom, halfDepth),
    ),
    ..._quad(
      normal: const Vector3(0, 0, -1),
      a: const Vector3(halfWidth, bottom, -halfDepth),
      b: const Vector3(halfWidth, top, -halfDepth),
      c: const Vector3(-halfWidth, top, -halfDepth),
      d: const Vector3(-halfWidth, bottom, -halfDepth),
    ),
    ..._quad(
      normal: const Vector3(1, 0, 0),
      a: const Vector3(halfWidth, bottom, halfDepth),
      b: const Vector3(halfWidth, top, halfDepth),
      c: const Vector3(halfWidth, top, -halfDepth),
      d: const Vector3(halfWidth, bottom, -halfDepth),
    ),
    ..._quad(
      normal: const Vector3(-1, 0, 0),
      a: const Vector3(-halfWidth, bottom, -halfDepth),
      b: const Vector3(-halfWidth, top, -halfDepth),
      c: const Vector3(-halfWidth, top, halfDepth),
      d: const Vector3(-halfWidth, bottom, halfDepth),
    ),
  ];
  return TexturedMeshPrototype(
    vertices: vertices,
    indices: const [
      0,
      1,
      2,
      0,
      2,
      3,
      4,
      5,
      6,
      4,
      6,
      7,
      8,
      9,
      10,
      8,
      10,
      11,
      12,
      13,
      14,
      12,
      14,
      15,
      16,
      17,
      18,
      16,
      18,
      19,
      20,
      21,
      22,
      20,
      22,
      23,
    ],
    material: material,
  );
}

List<MeshVertex> _quad({
  required Vector3 normal,
  required Vector3 a,
  required Vector3 b,
  required Vector3 c,
  required Vector3 d,
}) {
  return [
    MeshVertex(position: a, normal: normal, uv: Offset.zero),
    MeshVertex(position: b, normal: normal, uv: const Offset(6, 0)),
    MeshVertex(position: c, normal: normal, uv: const Offset(6, 6)),
    MeshVertex(position: d, normal: normal, uv: const Offset(0, 6)),
  ];
}

class _SceneHeader extends StatelessWidget {
  const _SceneHeader({required this.touchStatus, required this.compact});

  final String touchStatus;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xd9071527),
        border: Border.all(color: const Color(0x6638bdf8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'STAGE 3D',
              style: TextStyle(
                color: const Color(0xffe0f2fe),
                fontSize: compact ? 18 : 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              touchStatus,
              key: const ValueKey('touch-status'),
              style: const TextStyle(color: Color(0xff7dd3fc), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneInspector extends StatelessWidget {
  const _SceneInspector({
    required this.animations,
    required this.selectedIndex,
    required this.status,
    required this.onSelect,
  });

  final List<ModelAnimation> animations;
  final int selectedIndex;
  final String status;
  final ValueChanged<ModelAnimation> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xe6071527),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x8838bdf8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SCENE',
                style: TextStyle(
                  color: Color(0xffbae6fd),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              const _InspectorRow(label: 'Renderer', value: 'Filament'),
              const _InspectorRow(label: 'Physics', value: 'Jolt'),
              const _InspectorRow(label: 'Material', value: 'Grass wind'),
              const _InspectorRow(label: 'Mesh', value: 'Terrain'),
              const Divider(color: Color(0x3338bdf8), height: 18),
              const Text(
                'ANIMATION',
                style: TextStyle(
                  color: Color(0xffbae6fd),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                status,
                style: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
              ),
              if (animations.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final animation in animations)
                      ChoiceChip(
                        selected: animation.index == selectedIndex,
                        onSelected: (_) => onSelect(animation),
                        label: Text(
                          animation.name.isEmpty
                              ? 'Clip ${animation.index}'
                              : animation.name,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  const _InspectorRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xff64748b), fontSize: 10),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xffcbd5e1), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneToolbar extends StatelessWidget {
  const _SceneToolbar({
    required this.paused,
    required this.showInspector,
    required this.showColliders,
    required this.onTogglePause,
    required this.onResetModel,
    required this.onResetView,
    required this.onToggleInspector,
    required this.onToggleColliders,
  });

  final bool paused;
  final bool showInspector;
  final bool showColliders;
  final VoidCallback onTogglePause;
  final VoidCallback onResetModel;
  final VoidCallback onResetView;
  final VoidCallback onToggleInspector;
  final VoidCallback? onToggleColliders;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xee071527),
        border: Border.all(color: const Color(0x6638bdf8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              tooltip: paused ? 'Resume physics' : 'Pause physics',
              icon: paused ? Icons.play_arrow : Icons.pause,
              selected: !paused,
              onPressed: onTogglePause,
            ),
            _ToolbarButton(
              tooltip: 'Reset model',
              icon: Icons.restart_alt,
              onPressed: onResetModel,
            ),
            _ToolbarButton(
              tooltip: 'Reset view',
              icon: Icons.center_focus_strong,
              onPressed: onResetView,
            ),
            _ToolbarButton(
              tooltip: 'Scene inspector',
              icon: Icons.tune,
              selected: showInspector,
              onPressed: onToggleInspector,
            ),
            if (onToggleColliders != null)
              _ToolbarButton(
                tooltip: 'Collider map',
                icon: Icons.grid_view,
                selected: showColliders,
                onPressed: onToggleColliders!,
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: selected ? const Color(0xff7dd3fc) : const Color(0xff94a3b8),
        style: IconButton.styleFrom(
          fixedSize: const Size(42, 42),
          backgroundColor: selected
              ? const Color(0x2238bdf8)
              : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}
