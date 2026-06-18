import '../physics/physics_transform.dart';
import '../physics/vector3.dart';
import '../rendering/model_asset.dart';
import '../rendering/render_model_controller.dart';
import 'stage_component.dart';
import 'stage_object.dart';

/// Connects a [StageObject] to a Filament GLB model instance.
///
/// The component reads the owning object's transform each update and sends it
/// to the renderer, so physics and app logic can move one shared node.
final class RenderModelComponent extends StageComponent {
  /// Creates a render model component using a preloaded [asset].
  RenderModelComponent({
    required this.controller,
    required this.asset,
    this.visualOffset = Vector3.zero,
  });

  /// Controller that owns native model assets and instances.
  final RenderModelController controller;

  /// Shared loaded model asset.
  final RenderModelAsset asset;

  /// Local visual offset applied after the owning object's transform.
  ///
  /// This is useful when a GLB's visual origin does not line up perfectly with
  /// its physics body, for example a character model with feet below a capsule.
  final Vector3 visualOffset;

  RenderModelInstance? _instance;

  /// Visible renderer instance, if attached.
  RenderModelInstance? get instance => _instance;

  /// Visible renderer instance, or throws when the component is detached.
  RenderModelInstance get requireInstance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('RenderModelComponent is not attached.');
    }
    return instance;
  }

  @override
  void onAttach(StageObject object) {
    _instance = controller.createInstance(
      asset,
      transform: _visualTransform(object.transform.transform),
    );
  }

  @override
  void update(double deltaSeconds) {
    final instance = _instance;
    final object = this.object;
    if (instance == null || object == null) {
      return;
    }
    controller.setTransform(
      instance,
      _visualTransform(object.transform.transform),
    );
  }

  @override
  void onDetach() {
    final instance = _instance;
    if (instance != null) {
      controller.destroyInstance(instance);
      _instance = null;
    }
  }

  PhysicsTransform _visualTransform(PhysicsTransform transform) {
    return PhysicsTransform(
      position: transform.position.translate(
        visualOffset.x,
        visualOffset.y,
        visualOffset.z,
      ),
      rotation: transform.rotation,
    );
  }
}
