import 'package:flutter/services.dart';

import '../physics/physics_transform.dart';
import 'model_asset.dart';

/// Manages visual GLB assets and instances in the native Filament viewport.
///
/// This API is independent from [PhysicsWorld]. Applications may render static
/// architectural models without physics, or synchronize a model instance with
/// a rigid body each frame.
final class RenderModelController {
  MethodChannel? _channel;
  var _nextAssetId = 1;
  var _nextInstanceId = 1;
  final _assets = <int, RenderModelAsset>{};
  final _instances = <int, RenderModelInstance>{};

  /// Attaches to an initialized native viewport and recreates registered data.
  void attach(MethodChannel channel) {
    _channel = channel;
    for (final asset in _assets.values) {
      _loadNativeAsset(asset);
    }
    for (final instance in _instances.values) {
      _createNativeInstance(instance);
    }
  }

  /// Detaches while retaining Dart-side scene prototypes.
  void detach() {
    _channel = null;
  }

  /// Registers a GLB [settings] asset with the renderer.
  RenderModelAsset loadAsset(ModelAsset settings) {
    final asset = RenderModelAsset(
      id: ModelAssetId(_nextAssetId++),
      settings: settings,
    );
    _assets[asset.id.value] = asset;
    _loadNativeAsset(asset);
    return asset;
  }

  /// Creates one visible instance of [asset].
  RenderModelInstance createInstance(
    RenderModelAsset asset, {
    required PhysicsTransform transform,
  }) {
    final animationIndex = asset.settings.animationIndex;
    final instance = RenderModelInstance(
      id: ModelInstanceId(_nextInstanceId++),
      asset: asset,
      transform: transform,
      animation: animationIndex == null
          ? null
          : ModelAnimationPlayback(animationIndex: animationIndex),
    );
    _instances[instance.id.value] = instance;
    _createNativeInstance(instance);
    return instance;
  }

  /// Reads animation clips embedded in [instance]'s GLB asset.
  Future<List<ModelAnimation>> getAnimations(
    RenderModelInstance instance,
  ) async {
    final result = await _channel?.invokeListMethod<Object?>(
      'getModelAnimations',
      {'instanceId': instance.id.value},
    );
    return [
      for (final item in result ?? const <Object?>[])
        ModelAnimation.fromMessage(item! as Map<Object?, Object?>),
    ];
  }

  /// Starts or replaces animation playback for [instance].
  void playAnimation(
    RenderModelInstance instance, {
    required int animationIndex,
    bool loop = true,
    double speed = 1,
  }) {
    final playback = ModelAnimationPlayback(
      animationIndex: animationIndex,
      loop: loop,
      speed: speed,
    );
    instance.animation = playback;
    _channel?.invokeMethod<void>('playModelAnimation', {
      'instanceId': instance.id.value,
      ...playback.toMessage(),
    });
  }

  /// Temporarily freezes the current animation frame.
  void pauseAnimation(RenderModelInstance instance) {
    final playback = instance.animation;
    if (playback == null || playback.paused) {
      return;
    }
    instance.animation = playback.copyWith(paused: true);
    _channel?.invokeMethod<void>('pauseModelAnimation', {
      'instanceId': instance.id.value,
    });
  }

  /// Continues a paused animation from its current frame.
  void resumeAnimation(RenderModelInstance instance) {
    final playback = instance.animation;
    if (playback == null || !playback.paused) {
      return;
    }
    instance.animation = playback.copyWith(paused: false);
    _channel?.invokeMethod<void>('resumeModelAnimation', {
      'instanceId': instance.id.value,
    });
  }

  /// Stops animation playback for [instance].
  void stopAnimation(RenderModelInstance instance) {
    instance.animation = null;
    _channel?.invokeMethod<void>('stopModelAnimation', {
      'instanceId': instance.id.value,
    });
  }

  /// Updates the world-space [transform] of [instance].
  void setTransform(RenderModelInstance instance, PhysicsTransform transform) {
    instance.transform = transform;
    _channel?.invokeMethod<void>('setModelTransform', {
      'instanceId': instance.id.value,
      ..._transformMessage(transform),
    });
  }

  /// Removes [instance] from Dart and the renderer.
  void destroyInstance(RenderModelInstance instance) {
    _instances.remove(instance.id.value);
    _channel?.invokeMethod<void>('destroyModelInstance', {
      'instanceId': instance.id.value,
    });
  }

  void _loadNativeAsset(RenderModelAsset asset) {
    _channel?.invokeMethod<void>('loadModelAsset', {
      'assetId': asset.id.value,
      ...asset.settings.toMessage(),
    });
  }

  void _createNativeInstance(RenderModelInstance instance) {
    _channel?.invokeMethod<void>('createModelInstance', {
      'assetId': instance.asset.id.value,
      'instanceId': instance.id.value,
      ..._transformMessage(instance.transform),
      if (instance.animation case final animation?) ...animation.toMessage(),
    });
  }

  Map<String, Object> _transformMessage(PhysicsTransform transform) => {
    'x': transform.x,
    'y': transform.y,
    'z': transform.z,
    'qx': transform.qx,
    'qy': transform.qy,
    'qz': transform.qz,
    'qw': transform.qw,
  };
}
