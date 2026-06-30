#include <jni.h>

#include <cstdint>
#include <limits>

#include "stage_3d/stage_engine.h"

namespace {

StageEngine* FromHandle(jlong handle) {
  return reinterpret_cast<StageEngine*>(static_cast<intptr_t>(handle));
}

jlong Create() {
  return static_cast<jlong>(
      reinterpret_cast<intptr_t>(stage_engine_create()));
}

void Destroy(jlong handle) {
  stage_engine_destroy(FromHandle(handle));
}

void SetCamera(
    jlong handle,
    jfloat target_x,
    jfloat target_y,
    jfloat target_z,
    jfloat yaw,
    jfloat pitch,
    jfloat distance) {
  stage_engine_set_orbit_camera(
      FromHandle(handle),
      StageOrbitCamera{
          target_x, target_y, target_z, yaw, pitch, distance});
}

void OrbitCamera(jlong handle, jfloat delta_yaw, jfloat delta_pitch) {
  stage_engine_orbit_camera(
      FromHandle(handle), delta_yaw, delta_pitch);
}

void MoveCamera(jlong handle, jfloat delta_x, jfloat delta_y) {
  stage_engine_move_camera(FromHandle(handle), delta_x, delta_y);
}

jfloatArray GetCamera(JNIEnv* env, jlong handle) {
  const StageCamera camera = stage_engine_get_camera(FromHandle(handle));
  const jfloat values[] = {
      camera.eye_x,
      camera.eye_y,
      camera.eye_z,
      camera.target_x,
      camera.target_y,
      camera.target_z,
      camera.up_x,
      camera.up_y,
      camera.up_z,
      camera.vertical_fov_degrees,
      camera.near_plane,
      camera.far_plane,
  };
  jfloatArray result = env->NewFloatArray(12);
  env->SetFloatArrayRegion(result, 0, 12, values);
  return result;
}

void SetEnvironment(
    jlong handle,
    jfloat sky_r,
    jfloat sky_g,
    jfloat sky_b,
    jfloat sky_a,
    jfloat ambient_intensity,
    jfloat reflection_intensity) {
  stage_engine_set_environment(
      FromHandle(handle),
      StageEnvironment{
          sky_r,
          sky_g,
          sky_b,
          sky_a,
          ambient_intensity,
          reflection_intensity,
      });
}

jfloatArray GetEnvironment(JNIEnv* env, jlong handle) {
  const StageEnvironment environment =
      stage_engine_get_environment(FromHandle(handle));
  const jfloat values[] = {
      environment.sky_r,
      environment.sky_g,
      environment.sky_b,
      environment.sky_a,
      environment.ambient_intensity,
      environment.reflection_intensity,
  };
  jfloatArray result = env->NewFloatArray(6);
  env->SetFloatArrayRegion(result, 0, 6, values);
  return result;
}

void UpsertLight(
    jlong handle,
    jint id,
    jint type,
    jfloat color_r,
    jfloat color_g,
    jfloat color_b,
    jfloat intensity,
    jfloat position_x,
    jfloat position_y,
    jfloat position_z,
    jfloat direction_x,
    jfloat direction_y,
    jfloat direction_z,
    jfloat falloff_radius,
    jboolean cast_shadows) {
  stage_engine_upsert_light(
      FromHandle(handle),
      StageLight{
          id,
          type,
          color_r,
          color_g,
          color_b,
          intensity,
          position_x,
          position_y,
          position_z,
          direction_x,
          direction_y,
          direction_z,
          falloff_radius,
          static_cast<uint8_t>(cast_shadows == JNI_TRUE),
      });
}

void SetLightPosition(
    jlong handle,
    jint id,
    jfloat x,
    jfloat y,
    jfloat z) {
  stage_engine_set_light_position(FromHandle(handle), id, x, y, z);
}

void SetLightDirection(
    jlong handle,
    jint id,
    jfloat x,
    jfloat y,
    jfloat z) {
  stage_engine_set_light_direction(FromHandle(handle), id, x, y, z);
}

void SetLightIntensity(jlong handle, jint id, jfloat intensity) {
  stage_engine_set_light_intensity(FromHandle(handle), id, intensity);
}

jfloatArray GetLight(JNIEnv* env, jlong handle, jint id) {
  StageLight light{};
  if (stage_engine_get_light(FromHandle(handle), id, &light) == 0) {
    return nullptr;
  }
  const jfloat values[] = {
      static_cast<jfloat>(light.id),
      static_cast<jfloat>(light.type),
      light.color_r,
      light.color_g,
      light.color_b,
      light.intensity,
      light.position_x,
      light.position_y,
      light.position_z,
      light.direction_x,
      light.direction_y,
      light.direction_z,
      light.falloff_radius,
      static_cast<jfloat>(light.cast_shadows),
  };
  jfloatArray result = env->NewFloatArray(14);
  env->SetFloatArrayRegion(result, 0, 14, values);
  return result;
}

void RemoveLight(jlong handle, jint id) {
  stage_engine_remove_light(FromHandle(handle), id);
}

void RegisterModelAsset(
    jlong handle,
    jint asset_id,
    jfloat normalized_scale,
    jint vertical_anchor,
    jfloat center_x,
    jfloat center_y,
    jfloat center_z,
    jfloat half_extent_x,
    jfloat half_extent_y,
    jfloat half_extent_z) {
  stage_engine_register_model_asset(
      FromHandle(handle),
      asset_id,
      normalized_scale,
      vertical_anchor,
      StageModelBounds{
          center_x,
          center_y,
          center_z,
          half_extent_x,
          half_extent_y,
          half_extent_z,
      });
}

jboolean CreateModelInstance(
    jlong handle,
    jint instance_id,
    jint asset_id) {
  return stage_engine_create_model_instance(
             FromHandle(handle), instance_id, asset_id) != 0
             ? JNI_TRUE
             : JNI_FALSE;
}

void SetModelTransform(
    jlong handle,
    jint instance_id,
    jfloat x,
    jfloat y,
    jfloat z,
    jfloat qx,
    jfloat qy,
    jfloat qz,
    jfloat qw) {
  stage_engine_set_model_transform(
      FromHandle(handle),
      instance_id,
      StageModelTransform{x, y, z, qx, qy, qz, qw});
}

void FillModelMatrix(
    JNIEnv* env,
    jlong handle,
    jint instance_id,
    jfloatArray target) {
  if (target == nullptr || env->GetArrayLength(target) < 16) {
    return;
  }
  jfloat values[16]{};
  if (stage_engine_get_model_matrix(
          FromHandle(handle), instance_id, values) == 0) {
    return;
  }
  env->SetFloatArrayRegion(target, 0, 16, values);
}

void RemoveModelInstance(jlong handle, jint instance_id) {
  stage_engine_remove_model_instance(FromHandle(handle), instance_id);
}

jboolean RemoveModelAsset(jlong handle, jint asset_id) {
  return stage_engine_remove_model_asset(FromHandle(handle), asset_id) != 0
             ? JNI_TRUE
             : JNI_FALSE;
}

void PlayModelAnimation(
    jlong handle,
    jint instance_id,
    jint animation_index,
    jboolean loop,
    jfloat speed,
    jlong now_nanos,
    jboolean paused) {
  stage_engine_play_model_animation(
      FromHandle(handle),
      instance_id,
      animation_index,
      static_cast<uint8_t>(loop == JNI_TRUE),
      speed,
      now_nanos,
      static_cast<uint8_t>(paused == JNI_TRUE));
}

jfloat SampleModelAnimation(
    jlong handle,
    jint instance_id,
    jlong frame_time_nanos,
    jfloat duration_seconds) {
  int32_t animation_index = 0;
  float animation_time = 0.0f;
  if (stage_engine_sample_model_animation(
          FromHandle(handle),
          instance_id,
          frame_time_nanos,
          duration_seconds,
          &animation_index,
          &animation_time) == 0) {
    return std::numeric_limits<jfloat>::quiet_NaN();
  }
  return animation_time;
}

}  // namespace

#define STAGE_JNI_METHODS(PACKAGE)                                             \
  extern "C" JNIEXPORT jlong JNICALL                                          \
      Java_##PACKAGE##_NativeStageEngine_nativeCreate(JNIEnv*, jclass) {       \
    return Create();                                                           \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeDestroy(                        \
          JNIEnv*, jclass, jlong handle) {                                     \
    Destroy(handle);                                                           \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeResetCamera(                    \
          JNIEnv*, jclass, jlong handle) {                                     \
    stage_engine_reset_camera(FromHandle(handle));                             \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeSetCamera(                      \
          JNIEnv*, jclass, jlong handle, jfloat tx, jfloat ty, jfloat tz,      \
          jfloat yaw, jfloat pitch, jfloat distance) {                         \
    SetCamera(handle, tx, ty, tz, yaw, pitch, distance);                       \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeOrbitCamera(                    \
          JNIEnv*, jclass, jlong handle, jfloat yaw, jfloat pitch) {           \
    OrbitCamera(handle, yaw, pitch);                                           \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeMoveCamera(                     \
          JNIEnv*, jclass, jlong handle, jfloat x, jfloat y) {                 \
    MoveCamera(handle, x, y);                                                  \
  }                                                                            \
  extern "C" JNIEXPORT jfloatArray JNICALL                                    \
      Java_##PACKAGE##_NativeStageEngine_nativeGetCamera(                      \
          JNIEnv* env, jclass, jlong handle) {                                 \
    return GetCamera(env, handle);                                             \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeSetEnvironment(                 \
          JNIEnv*, jclass, jlong handle, jfloat r, jfloat g, jfloat b,         \
          jfloat a, jfloat ambient, jfloat reflection) {                       \
    SetEnvironment(handle, r, g, b, a, ambient, reflection);                   \
  }                                                                            \
  extern "C" JNIEXPORT jfloatArray JNICALL                                    \
      Java_##PACKAGE##_NativeStageEngine_nativeGetEnvironment(                 \
          JNIEnv* env, jclass, jlong handle) {                                 \
    return GetEnvironment(env, handle);                                        \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeUpsertLight(                    \
          JNIEnv*, jclass, jlong handle, jint id, jint type, jfloat r,         \
          jfloat g, jfloat b, jfloat intensity, jfloat px, jfloat py,          \
          jfloat pz, jfloat dx, jfloat dy, jfloat dz, jfloat falloff,          \
          jboolean shadows) {                                                  \
    UpsertLight(                                                               \
        handle, id, type, r, g, b, intensity, px, py, pz, dx, dy, dz,         \
        falloff, shadows);                                                     \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeSetLightPosition(               \
          JNIEnv*, jclass, jlong handle, jint id, jfloat x, jfloat y,          \
          jfloat z) {                                                          \
    SetLightPosition(handle, id, x, y, z);                                     \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeSetLightDirection(              \
          JNIEnv*, jclass, jlong handle, jint id, jfloat x, jfloat y,          \
          jfloat z) {                                                          \
    SetLightDirection(handle, id, x, y, z);                                    \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeSetLightIntensity(              \
          JNIEnv*, jclass, jlong handle, jint id, jfloat intensity) {          \
    SetLightIntensity(handle, id, intensity);                                  \
  }                                                                            \
  extern "C" JNIEXPORT jfloatArray JNICALL                                    \
      Java_##PACKAGE##_NativeStageEngine_nativeGetLight(                       \
          JNIEnv* env, jclass, jlong handle, jint id) {                        \
    return GetLight(env, handle, id);                                          \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeRemoveLight(                    \
          JNIEnv*, jclass, jlong handle, jint id) {                            \
    RemoveLight(handle, id);                                                   \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeRegisterModelAsset(             \
          JNIEnv*, jclass, jlong handle, jint asset_id, jfloat scale,          \
          jint anchor, jfloat cx, jfloat cy, jfloat cz, jfloat ex, jfloat ey,  \
          jfloat ez) {                                                         \
    RegisterModelAsset(                                                        \
        handle, asset_id, scale, anchor, cx, cy, cz, ex, ey, ez);              \
  }                                                                            \
  extern "C" JNIEXPORT jboolean JNICALL                                       \
      Java_##PACKAGE##_NativeStageEngine_nativeCreateModelInstance(            \
          JNIEnv*, jclass, jlong handle, jint instance_id, jint asset_id) {    \
    return CreateModelInstance(handle, instance_id, asset_id);                 \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeSetModelTransform(              \
          JNIEnv*, jclass, jlong handle, jint instance_id, jfloat x, jfloat y, \
          jfloat z, jfloat qx, jfloat qy, jfloat qz, jfloat qw) {              \
    SetModelTransform(handle, instance_id, x, y, z, qx, qy, qz, qw);          \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeFillModelMatrix(                \
          JNIEnv* env, jclass, jlong handle, jint instance_id,                 \
          jfloatArray target) {                                                \
    FillModelMatrix(env, handle, instance_id, target);                         \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeRemoveModelInstance(            \
          JNIEnv*, jclass, jlong handle, jint instance_id) {                   \
    RemoveModelInstance(handle, instance_id);                                  \
  }                                                                            \
  extern "C" JNIEXPORT jboolean JNICALL                                       \
      Java_##PACKAGE##_NativeStageEngine_nativeRemoveModelAsset(               \
          JNIEnv*, jclass, jlong handle, jint asset_id) {                      \
    return RemoveModelAsset(handle, asset_id);                                 \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativePlayModelAnimation(             \
          JNIEnv*, jclass, jlong handle, jint instance_id,                     \
          jint animation_index, jboolean loop, jfloat speed, jlong now_nanos,  \
          jboolean paused) {                                                   \
    PlayModelAnimation(                                                        \
        handle, instance_id, animation_index, loop, speed, now_nanos, paused); \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativePauseModelAnimation(            \
          JNIEnv*, jclass, jlong handle, jint instance_id, jlong now_nanos) {  \
    stage_engine_pause_model_animation(                                        \
        FromHandle(handle), instance_id, now_nanos);                           \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeResumeModelAnimation(           \
          JNIEnv*, jclass, jlong handle, jint instance_id, jlong now_nanos) {  \
    stage_engine_resume_model_animation(                                       \
        FromHandle(handle), instance_id, now_nanos);                           \
  }                                                                            \
  extern "C" JNIEXPORT void JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeStopModelAnimation(             \
          JNIEnv*, jclass, jlong handle, jint instance_id) {                   \
    stage_engine_stop_model_animation(FromHandle(handle), instance_id);        \
  }                                                                            \
  extern "C" JNIEXPORT jint JNICALL                                           \
      Java_##PACKAGE##_NativeStageEngine_nativeGetModelAnimationIndex(         \
          JNIEnv*, jclass, jlong handle, jint instance_id) {                   \
    return stage_engine_get_model_animation_index(                             \
        FromHandle(handle), instance_id);                                      \
  }                                                                            \
  extern "C" JNIEXPORT jfloat JNICALL                                         \
      Java_##PACKAGE##_NativeStageEngine_nativeSampleModelAnimationTime(       \
          JNIEnv*, jclass, jlong handle, jint instance_id,                     \
          jlong frame_time_nanos, jfloat duration_seconds) {                   \
    return SampleModelAnimation(                                               \
        handle, instance_id, frame_time_nanos, duration_seconds);              \
  }

STAGE_JNI_METHODS(com_stage3d_stage_13d)
STAGE_JNI_METHODS(com_example_jolt_1physics_1dart)
