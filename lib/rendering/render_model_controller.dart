import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../physics/physics_transform.dart';
import 'model_asset.dart';
import 'render_scene_bridge.dart';

/// Manages visual GLB assets and instances in the native Filament viewport.
///
/// This API is independent from [PhysicsWorld]. Applications may render static
/// architectural models without physics, or synchronize a model instance with
/// a rigid body each frame.
final class RenderModelController {
  RenderSceneBridge? _bridge;
  var _nextAssetId = 1;
  var _nextInstanceId = 1;
  final _assets = <int, RenderModelAsset>{};
  final _instances = <int, RenderModelInstance>{};

  /// Attaches to an initialized native viewport and recreates registered data.
  void attach(MethodChannel channel) {
    attachBridge(MethodChannelRenderSceneBridge(channel));
  }

  /// Attaches to a renderer bridge and recreates registered data.
  void attachBridge(RenderSceneBridge bridge) {
    _bridge = bridge;
    for (final asset in _assets.values) {
      _loadBridgeAsset(asset);
    }
    for (final instance in _instances.values) {
      _createBridgeInstance(instance);
    }
  }

  /// Detaches while retaining Dart-side scene prototypes.
  void detach() {
    _bridge = null;
  }

  /// Registers a GLB [settings] asset with the renderer.
  RenderModelAsset loadAsset(ModelAsset settings) {
    final asset = RenderModelAsset(
      id: ModelAssetId(_nextAssetId++),
      settings: settings,
    );
    _assets[asset.id.value] = asset;
    _loadBridgeAsset(asset);
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
    _createBridgeInstance(instance);
    return instance;
  }

  /// Reads animation clips embedded in [instance]'s GLB asset.
  Future<List<ModelAnimation>> getAnimations(
    RenderModelInstance instance,
  ) async {
    return _bridge?.getModelAnimations(instance.id) ?? Future.value(const []);
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
    _bridge?.playModelAnimation(instance.id, playback);
  }

  /// Temporarily freezes the current animation frame.
  void pauseAnimation(RenderModelInstance instance) {
    final playback = instance.animation;
    if (playback == null || playback.paused) {
      return;
    }
    instance.animation = playback.copyWith(paused: true);
    _bridge?.pauseModelAnimation(instance.id);
  }

  /// Continues a paused animation from its current frame.
  void resumeAnimation(RenderModelInstance instance) {
    final playback = instance.animation;
    if (playback == null || !playback.paused) {
      return;
    }
    instance.animation = playback.copyWith(paused: false);
    _bridge?.resumeModelAnimation(instance.id);
  }

  /// Stops animation playback for [instance].
  void stopAnimation(RenderModelInstance instance) {
    instance.animation = null;
    _bridge?.stopModelAnimation(instance.id);
  }

  /// Updates the world-space [transform] of [instance].
  void setTransform(RenderModelInstance instance, PhysicsTransform transform) {
    instance.transform = transform;
    _bridge?.setModelTransform(instance.id, transform);
  }

  /// Removes [instance] from Dart and the renderer.
  void destroyInstance(RenderModelInstance instance) {
    _instances.remove(instance.id.value);
    _bridge?.destroyModelInstance(instance.id);
  }

  /// Releases [asset] after all of its instances have been destroyed.
  void unloadAsset(RenderModelAsset asset) {
    final isUsed = _instances.values.any(
      (instance) => instance.asset.id.value == asset.id.value,
    );
    if (isUsed) {
      throw StateError(
        'Cannot unload model asset ${asset.id.value} while instances use it.',
      );
    }
    if (_assets.remove(asset.id.value) == null) {
      return;
    }
    _bridge?.unloadModelAsset(asset.id);
  }

  void _loadBridgeAsset(RenderModelAsset asset) {
    _bridge?.loadModelAsset(asset).catchError((Object error, StackTrace stack) {
      debugPrint(
        'Stage 3D renderer failed to load ${asset.settings.assetPath}: $error',
      );
    });
  }

  void _createBridgeInstance(RenderModelInstance instance) {
    _bridge?.createModelInstance(instance).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint(
        'Stage 3D renderer failed to create model instance '
        '${instance.id.value}: $error',
      );
    });
  }
}
