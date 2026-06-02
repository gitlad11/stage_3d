import '../physics/physics_transform.dart';

/// Reusable description of a visual model available to the renderer.
///
/// Filament currently loads binary glTF (`.glb`) files from Android assets.
/// Convert FBX, OBJ, and Blender files to GLB before packaging them.
final class ModelAsset {
  /// Creates a model asset prototype.
  const ModelAsset({
    required this.assetPath,
    this.normalizedScale = 1,
    this.animationIndex,
  }) : assert(normalizedScale > 0);

  /// Android asset path, for example `models/Fox.glb`.
  final String assetPath;

  /// Scale applied after fitting the model inside a normalized unit cube.
  final double normalizedScale;

  /// Optional glTF animation clip played in a loop.
  final int? animationIndex;

  /// Serializes asset settings for the native renderer bridge.
  Map<String, Object?> toMessage() => {
    'assetPath': assetPath,
    'normalizedScale': normalizedScale,
    'animationIndex': animationIndex,
  };
}

/// Stable identifier for a renderer asset.
final class ModelAssetId {
  /// Creates an asset identifier.
  const ModelAssetId(this.value);

  /// Renderer-specific identifier.
  final int value;
}

/// Stable identifier for one visual model instance.
final class ModelInstanceId {
  /// Creates an instance identifier.
  const ModelInstanceId(this.value);

  /// Renderer-specific identifier.
  final int value;
}

/// Loaded visual model asset owned by a renderer.
final class RenderModelAsset {
  /// Creates a loaded asset handle.
  const RenderModelAsset({required this.id, required this.settings});

  /// Identifier used for renderer operations.
  final ModelAssetId id;

  /// Immutable source settings.
  final ModelAsset settings;
}

/// One visible occurrence of a loaded [RenderModelAsset].
///
/// A single room or furniture asset can have many instances with independent
/// transforms.
final class RenderModelInstance {
  /// Creates a visible instance handle.
  RenderModelInstance({
    required this.id,
    required this.asset,
    required this.transform,
    this.animation,
  });

  /// Identifier used for renderer operations.
  final ModelInstanceId id;

  /// Shared loaded asset used by this instance.
  final RenderModelAsset asset;

  /// Latest world-space transform.
  PhysicsTransform transform;

  /// Latest requested animation playback, or `null` when stopped.
  ModelAnimationPlayback? animation;
}

/// One animation clip embedded in a GLB model.
final class ModelAnimation {
  /// Creates animation metadata returned by Filament.
  const ModelAnimation({
    required this.index,
    required this.name,
    required this.durationSeconds,
  });

  /// Creates metadata from a native renderer message.
  factory ModelAnimation.fromMessage(Map<Object?, Object?> message) {
    return ModelAnimation(
      index: message['index']! as int,
      name: message['name']! as String,
      durationSeconds: (message['durationSeconds']! as num).toDouble(),
    );
  }

  /// Zero-based clip index used by Filament Animator.
  final int index;

  /// Clip name embedded in the GLB file.
  final String name;

  /// Clip duration in seconds.
  final double durationSeconds;
}

/// Playback settings for one visible model instance.
final class ModelAnimationPlayback {
  /// Creates playback settings.
  const ModelAnimationPlayback({
    required this.animationIndex,
    this.loop = true,
    this.speed = 1,
    this.paused = false,
  }) : assert(animationIndex >= 0),
       assert(speed > 0);

  /// Selected zero-based clip index.
  final int animationIndex;

  /// Whether playback restarts after reaching the clip end.
  final bool loop;

  /// Playback time multiplier.
  final double speed;

  /// Whether animation time is temporarily frozen.
  final bool paused;

  /// Returns a copy with selected fields changed.
  ModelAnimationPlayback copyWith({
    int? animationIndex,
    bool? loop,
    double? speed,
    bool? paused,
  }) {
    return ModelAnimationPlayback(
      animationIndex: animationIndex ?? this.animationIndex,
      loop: loop ?? this.loop,
      speed: speed ?? this.speed,
      paused: paused ?? this.paused,
    );
  }

  /// Serializes playback settings for the native renderer bridge.
  Map<String, Object> toMessage() => {
    'animationIndex': animationIndex,
    'loop': loop,
    'speed': speed,
    'paused': paused,
  };
}
