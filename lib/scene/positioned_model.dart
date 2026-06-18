import '../physics/physics_transform.dart';
import '../physics/vector3.dart';
import '../rendering/model_asset.dart';
import '../rendering/render_model_controller.dart';
import 'render_model_component.dart';

/// A GLB model placed in a local node coordinate system.
///
/// The model follows the owning [StageObject]'s transform while keeping this
/// local offset. This mirrors the same idea as [PositionedShape] for physics.
final class PositionedModel {
  /// Creates a locally positioned render model part.
  const PositionedModel({
    required this.asset,
    this.position = Vector3.zero,
    this.rotation = Quaternion.identity,
  });

  /// Loaded reusable model asset.
  final RenderModelAsset asset;

  /// Local position relative to the owning node origin.
  final Vector3 position;

  /// Local rotation reserved for future renderer-side child transforms.
  final Quaternion rotation;

  /// Creates a component that can be attached to a [StageObject].
  RenderModelComponent toComponent(RenderModelController controller) {
    return RenderModelComponent(
      controller: controller,
      asset: asset,
      visualOffset: position,
    );
  }
}
