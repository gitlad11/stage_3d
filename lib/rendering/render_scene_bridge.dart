import 'package:flutter/services.dart';

import '../physics/physics_transform.dart';
import '../physics/vector3.dart';
import 'light.dart';
import 'model_asset.dart';
import 'textured_mesh_prototype.dart';

/// Renderer backend contract used by Dart scene controllers.
///
/// Applications can use [MethodChannelRenderSceneBridge] for the built-in
/// Android Filament viewport, or implement this interface for a custom native
/// renderer while keeping the same Dart model, mesh, material, and light APIs.
abstract interface class RenderSceneBridge {
  /// Resets the active renderer camera/view state.
  Future<void> resetView();

  /// Loads a reusable visual asset.
  Future<void> loadModelAsset(RenderModelAsset asset);

  /// Creates a visible model instance.
  Future<void> createModelInstance(RenderModelInstance instance);

  /// Updates a model instance transform.
  Future<void> setModelTransform(
    ModelInstanceId instanceId,
    PhysicsTransform transform,
  );

  /// Removes a model instance from the renderer.
  Future<void> destroyModelInstance(ModelInstanceId instanceId);

  /// Reads available animation clips from a model instance.
  Future<List<ModelAnimation>> getModelAnimations(ModelInstanceId instanceId);

  /// Starts or replaces model animation playback.
  Future<void> playModelAnimation(
    ModelInstanceId instanceId,
    ModelAnimationPlayback playback,
  );

  /// Pauses model animation playback.
  Future<void> pauseModelAnimation(ModelInstanceId instanceId);

  /// Resumes paused model animation playback.
  Future<void> resumeModelAnimation(ModelInstanceId instanceId);

  /// Stops model animation playback.
  Future<void> stopModelAnimation(ModelInstanceId instanceId);

  /// Creates or replaces a procedural textured mesh.
  Future<void> createTexturedMesh(int meshId, TexturedMeshPrototype mesh);

  /// Removes a procedural textured mesh.
  Future<void> destroyTexturedMesh(int meshId);

  /// Creates a renderer light.
  Future<void> createLight(RenderLight light);

  /// Moves a point light.
  Future<void> setLightPosition(LightId lightId, Vector3 position);

  /// Updates a directional light direction.
  Future<void> setLightDirection(LightId lightId, Vector3 direction);

  /// Updates light intensity.
  Future<void> setLightIntensity(LightId lightId, double intensity);

  /// Removes a renderer light.
  Future<void> destroyLight(LightId lightId);
}

/// [RenderSceneBridge] implementation backed by a Flutter [MethodChannel].
///
/// This is the bridge used by the bundled Android Filament viewport. Custom
/// Kotlin/Filament renderers can either reuse the same method names or provide
/// their own [RenderSceneBridge] implementation.
final class MethodChannelRenderSceneBridge implements RenderSceneBridge {
  /// Creates a bridge for [channel].
  const MethodChannelRenderSceneBridge(this.channel);

  /// Native renderer channel.
  final MethodChannel channel;

  @override
  Future<void> resetView() => channel.invokeMethod<void>('resetView');

  @override
  Future<void> loadModelAsset(RenderModelAsset asset) =>
      channel.invokeMethod<void>('loadModelAsset', {
        'assetId': asset.id.value,
        ...asset.settings.toMessage(),
      });

  @override
  Future<void> createModelInstance(RenderModelInstance instance) =>
      channel.invokeMethod<void>('createModelInstance', {
        'assetId': instance.asset.id.value,
        'instanceId': instance.id.value,
        ..._transformMessage(instance.transform),
        if (instance.animation case final animation?) ...animation.toMessage(),
      });

  @override
  Future<void> setModelTransform(
    ModelInstanceId instanceId,
    PhysicsTransform transform,
  ) => channel.invokeMethod<void>('setModelTransform', {
    'instanceId': instanceId.value,
    ..._transformMessage(transform),
  });

  @override
  Future<void> destroyModelInstance(ModelInstanceId instanceId) =>
      channel.invokeMethod<void>('destroyModelInstance', {
        'instanceId': instanceId.value,
      });

  @override
  Future<List<ModelAnimation>> getModelAnimations(
    ModelInstanceId instanceId,
  ) async {
    final result = await channel.invokeListMethod<Object?>(
      'getModelAnimations',
      {'instanceId': instanceId.value},
    );
    return [
      for (final item in result ?? const <Object?>[])
        ModelAnimation.fromMessage(item! as Map<Object?, Object?>),
    ];
  }

  @override
  Future<void> playModelAnimation(
    ModelInstanceId instanceId,
    ModelAnimationPlayback playback,
  ) => channel.invokeMethod<void>('playModelAnimation', {
    'instanceId': instanceId.value,
    ...playback.toMessage(),
  });

  @override
  Future<void> pauseModelAnimation(ModelInstanceId instanceId) =>
      channel.invokeMethod<void>('pauseModelAnimation', {
        'instanceId': instanceId.value,
      });

  @override
  Future<void> resumeModelAnimation(ModelInstanceId instanceId) =>
      channel.invokeMethod<void>('resumeModelAnimation', {
        'instanceId': instanceId.value,
      });

  @override
  Future<void> stopModelAnimation(ModelInstanceId instanceId) =>
      channel.invokeMethod<void>('stopModelAnimation', {
        'instanceId': instanceId.value,
      });

  @override
  Future<void> createTexturedMesh(int meshId, TexturedMeshPrototype mesh) =>
      channel.invokeMethod<void>('createTexturedMesh', {
        'meshId': meshId,
        ...mesh.toMessage(),
      });

  @override
  Future<void> destroyTexturedMesh(int meshId) =>
      channel.invokeMethod<void>('destroyTexturedMesh', {'meshId': meshId});

  @override
  Future<void> createLight(RenderLight light) => channel.invokeMethod<void>(
    'createLight',
    {'id': light.id.value, ...light.settings.toMessage()},
  );

  @override
  Future<void> setLightPosition(LightId lightId, Vector3 position) =>
      channel.invokeMethod<void>('setLightPosition', {
        'id': lightId.value,
        'x': position.x,
        'y': position.y,
        'z': position.z,
      });

  @override
  Future<void> setLightDirection(LightId lightId, Vector3 direction) =>
      channel.invokeMethod<void>('setLightDirection', {
        'id': lightId.value,
        'x': direction.x,
        'y': direction.y,
        'z': direction.z,
      });

  @override
  Future<void> setLightIntensity(LightId lightId, double intensity) =>
      channel.invokeMethod<void>('setLightIntensity', {
        'id': lightId.value,
        'intensity': intensity,
      });

  @override
  Future<void> destroyLight(LightId lightId) =>
      channel.invokeMethod<void>('destroyLight', {'id': lightId.value});
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
