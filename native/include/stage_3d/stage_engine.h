#ifndef STAGE_3D_STAGE_ENGINE_H_
#define STAGE_3D_STAGE_ENGINE_H_

#include <stdint.h>

#if defined(_WIN32)
#define STAGE_EXPORT __declspec(dllexport)
#else
#define STAGE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct StageEngine StageEngine;

typedef struct StageViewport {
  uint32_t width;
  uint32_t height;
  float pixel_ratio;
} StageViewport;

typedef struct StageCamera {
  float eye_x;
  float eye_y;
  float eye_z;
  float target_x;
  float target_y;
  float target_z;
  float up_x;
  float up_y;
  float up_z;
  float vertical_fov_degrees;
  float near_plane;
  float far_plane;
} StageCamera;

typedef struct StageOrbitCamera {
  float target_x;
  float target_y;
  float target_z;
  float yaw;
  float pitch;
  float distance;
} StageOrbitCamera;

typedef struct StageEnvironment {
  float sky_r;
  float sky_g;
  float sky_b;
  float sky_a;
  float ambient_intensity;
  float reflection_intensity;
} StageEnvironment;

typedef enum StageLightType {
  STAGE_LIGHT_DIRECTIONAL = 0,
  STAGE_LIGHT_POINT = 1,
} StageLightType;

typedef struct StageLight {
  int32_t id;
  int32_t type;
  float color_r;
  float color_g;
  float color_b;
  float intensity;
  float position_x;
  float position_y;
  float position_z;
  float direction_x;
  float direction_y;
  float direction_z;
  float falloff_radius;
  uint8_t cast_shadows;
} StageLight;

typedef enum StageModelVerticalAnchor {
  STAGE_MODEL_ANCHOR_ORIGIN = 0,
  STAGE_MODEL_ANCHOR_CENTER = 1,
  STAGE_MODEL_ANCHOR_BOTTOM = 2,
} StageModelVerticalAnchor;

typedef struct StageModelBounds {
  float center_x;
  float center_y;
  float center_z;
  float half_extent_x;
  float half_extent_y;
  float half_extent_z;
} StageModelBounds;

typedef struct StageModelTransform {
  float position_x;
  float position_y;
  float position_z;
  float rotation_x;
  float rotation_y;
  float rotation_z;
  float rotation_w;
} StageModelTransform;

STAGE_EXPORT StageEngine* stage_engine_create(void);
STAGE_EXPORT void stage_engine_destroy(StageEngine* engine);

STAGE_EXPORT void stage_engine_set_viewport(
    StageEngine* engine,
    StageViewport viewport);
STAGE_EXPORT StageViewport stage_engine_get_viewport(const StageEngine* engine);

STAGE_EXPORT void stage_engine_set_camera(
    StageEngine* engine,
    StageCamera camera);
STAGE_EXPORT StageCamera stage_engine_get_camera(const StageEngine* engine);

STAGE_EXPORT void stage_engine_set_orbit_camera(
    StageEngine* engine,
    StageOrbitCamera camera);
STAGE_EXPORT StageOrbitCamera stage_engine_get_orbit_camera(
    const StageEngine* engine);
STAGE_EXPORT void stage_engine_orbit_camera(
    StageEngine* engine,
    float delta_yaw,
    float delta_pitch);
STAGE_EXPORT void stage_engine_move_camera(
    StageEngine* engine,
    float delta_x,
    float delta_y);
STAGE_EXPORT void stage_engine_reset_camera(StageEngine* engine);

STAGE_EXPORT void stage_engine_set_environment(
    StageEngine* engine,
    StageEnvironment environment);
STAGE_EXPORT StageEnvironment stage_engine_get_environment(
    const StageEngine* engine);

STAGE_EXPORT void stage_engine_upsert_light(
    StageEngine* engine,
    StageLight light);
STAGE_EXPORT uint8_t stage_engine_get_light(
    const StageEngine* engine,
    int32_t id,
    StageLight* out_light);
STAGE_EXPORT void stage_engine_set_light_position(
    StageEngine* engine,
    int32_t id,
    float x,
    float y,
    float z);
STAGE_EXPORT void stage_engine_set_light_direction(
    StageEngine* engine,
    int32_t id,
    float x,
    float y,
    float z);
STAGE_EXPORT void stage_engine_set_light_intensity(
    StageEngine* engine,
    int32_t id,
    float intensity);
STAGE_EXPORT void stage_engine_remove_light(StageEngine* engine, int32_t id);
STAGE_EXPORT uint32_t stage_engine_light_count(const StageEngine* engine);

STAGE_EXPORT void stage_engine_register_model_asset(
    StageEngine* engine,
    int32_t asset_id,
    float normalized_scale,
    int32_t vertical_anchor,
    StageModelBounds bounds);
STAGE_EXPORT uint8_t stage_engine_has_model_asset(
    const StageEngine* engine,
    int32_t asset_id);
STAGE_EXPORT uint8_t stage_engine_remove_model_asset(
    StageEngine* engine,
    int32_t asset_id);

STAGE_EXPORT uint8_t stage_engine_create_model_instance(
    StageEngine* engine,
    int32_t instance_id,
    int32_t asset_id);
STAGE_EXPORT void stage_engine_set_model_transform(
    StageEngine* engine,
    int32_t instance_id,
    StageModelTransform transform);
STAGE_EXPORT uint8_t stage_engine_get_model_matrix(
    const StageEngine* engine,
    int32_t instance_id,
    float* out_matrix_16);
STAGE_EXPORT void stage_engine_remove_model_instance(
    StageEngine* engine,
    int32_t instance_id);
STAGE_EXPORT uint32_t stage_engine_model_asset_count(
    const StageEngine* engine);
STAGE_EXPORT uint32_t stage_engine_model_instance_count(
    const StageEngine* engine);

STAGE_EXPORT void stage_engine_play_model_animation(
    StageEngine* engine,
    int32_t instance_id,
    int32_t animation_index,
    uint8_t loop,
    float speed,
    int64_t now_nanos,
    uint8_t paused);
STAGE_EXPORT void stage_engine_pause_model_animation(
    StageEngine* engine,
    int32_t instance_id,
    int64_t now_nanos);
STAGE_EXPORT void stage_engine_resume_model_animation(
    StageEngine* engine,
    int32_t instance_id,
    int64_t now_nanos);
STAGE_EXPORT void stage_engine_stop_model_animation(
    StageEngine* engine,
    int32_t instance_id);
STAGE_EXPORT int32_t stage_engine_get_model_animation_index(
    const StageEngine* engine,
    int32_t instance_id);
STAGE_EXPORT uint8_t stage_engine_sample_model_animation(
    const StageEngine* engine,
    int32_t instance_id,
    int64_t frame_time_nanos,
    float duration_seconds,
    int32_t* out_animation_index,
    float* out_animation_time);

STAGE_EXPORT uint32_t stage_engine_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif  // STAGE_3D_STAGE_ENGINE_H_
