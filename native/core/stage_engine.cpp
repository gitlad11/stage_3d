#include "stage_3d/stage_engine.h"

#include <algorithm>
#include <cmath>
#include <new>
#include <unordered_map>

namespace {

constexpr uint32_t kStageEngineAbiVersion = 5;
constexpr float kMinPitch = -1.45f;
constexpr float kMaxPitch = 1.45f;

StageCamera DefaultCamera() {
  return StageCamera{
      0.0f, 0.0f, 4.0f,
      0.0f, 0.0f, 0.0f,
      0.0f, 1.0f, 0.0f,
      45.0f, 0.05f, 1000.0f,
  };
}

StageOrbitCamera DefaultOrbitCamera() {
  return StageOrbitCamera{0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 4.0f};
}

StageEnvironment DefaultEnvironment() {
  return StageEnvironment{
      0.16f, 0.48f, 0.78f, 1.0f,
      30000.0f, 0.9f,
  };
}

StageOrbitCamera NormalizeOrbitCamera(StageOrbitCamera camera) {
  camera.pitch = std::clamp(camera.pitch, kMinPitch, kMaxPitch);
  camera.distance = std::max(camera.distance, 0.1f);
  return camera;
}

StageCamera CameraFromOrbit(StageOrbitCamera orbit) {
  const float horizontal = std::cos(orbit.pitch) * orbit.distance;
  return StageCamera{
      orbit.target_x + std::sin(orbit.yaw) * horizontal,
      orbit.target_y + std::sin(orbit.pitch) * orbit.distance,
      orbit.target_z + std::cos(orbit.yaw) * horizontal,
      orbit.target_x,
      orbit.target_y,
      orbit.target_z,
      0.0f,
      1.0f,
      0.0f,
      45.0f,
      0.05f,
      1000.0f,
  };
}

StageLight NormalizeLight(StageLight light) {
  light.type =
      light.type == STAGE_LIGHT_POINT ? STAGE_LIGHT_POINT
                                      : STAGE_LIGHT_DIRECTIONAL;
  light.intensity = std::max(light.intensity, 0.0f);
  light.falloff_radius = std::max(light.falloff_radius, 0.001f);
  light.cast_shadows = light.cast_shadows == 0 ? 0 : 1;
  return light;
}

struct ModelAssetState {
  float normalized_scale;
  int32_t vertical_anchor;
  StageModelBounds bounds;
};

struct ModelInstanceState {
  int32_t asset_id;
  StageModelTransform transform{
      0.0f, 0.0f, 0.0f,
      0.0f, 0.0f, 0.0f, 1.0f,
  };
  struct AnimationState {
    int32_t animation_index;
    bool loop;
    float speed;
    int64_t started_at_nanos;
    int64_t paused_at_nanos;
    bool paused;
  };
  bool has_animation = false;
  AnimationState animation{};
};

int32_t NormalizeVerticalAnchor(int32_t anchor) {
  switch (anchor) {
    case STAGE_MODEL_ANCHOR_ORIGIN:
    case STAGE_MODEL_ANCHOR_BOTTOM:
      return anchor;
    default:
      return STAGE_MODEL_ANCHOR_CENTER;
  }
}

void BuildModelMatrix(
    const ModelAssetState& asset,
    const StageModelTransform& transform,
    float* matrix) {
  const float max_extent =
      std::max(
          {asset.bounds.half_extent_x,
           asset.bounds.half_extent_y,
           asset.bounds.half_extent_z}) *
      2.0f;
  const float scale =
      asset.normalized_scale * 2.0f / std::max(max_extent, 0.000001f);

  float anchor_x = asset.bounds.center_x;
  float anchor_y = asset.bounds.center_y;
  float anchor_z = asset.bounds.center_z;
  if (asset.vertical_anchor == STAGE_MODEL_ANCHOR_ORIGIN) {
    anchor_x = 0.0f;
    anchor_y = 0.0f;
    anchor_z = 0.0f;
  } else if (asset.vertical_anchor == STAGE_MODEL_ANCHOR_BOTTOM) {
    anchor_y -= asset.bounds.half_extent_y;
  }

  const float qx = transform.rotation_x;
  const float qy = transform.rotation_y;
  const float qz = transform.rotation_z;
  const float qw = transform.rotation_w;
  const float m00 = 1.0f - 2.0f * (qy * qy + qz * qz);
  const float m01 = 2.0f * (qx * qy - qz * qw);
  const float m02 = 2.0f * (qx * qz + qy * qw);
  const float m10 = 2.0f * (qx * qy + qz * qw);
  const float m11 = 1.0f - 2.0f * (qx * qx + qz * qz);
  const float m12 = 2.0f * (qy * qz - qx * qw);
  const float m20 = 2.0f * (qx * qz - qy * qw);
  const float m21 = 2.0f * (qy * qz + qx * qw);
  const float m22 = 1.0f - 2.0f * (qx * qx + qy * qy);

  const float target_x = transform.position_x * 0.12f;
  const float target_y = (transform.position_y - 0.65f) * 0.12f - 0.15f;
  const float target_z = -4.0f - transform.position_z * 0.12f;
  const float tx =
      target_x - scale * (m00 * anchor_x + m01 * anchor_y + m02 * anchor_z);
  const float ty =
      target_y - scale * (m10 * anchor_x + m11 * anchor_y + m12 * anchor_z);
  const float tz =
      target_z - scale * (m20 * anchor_x + m21 * anchor_y + m22 * anchor_z);

  const float values[16] = {
      scale * m00, scale * m10, scale * m20, 0.0f,
      scale * m01, scale * m11, scale * m21, 0.0f,
      scale * m02, scale * m12, scale * m22, 0.0f,
      tx,          ty,          tz,          1.0f,
  };
  std::copy(values, values + 16, matrix);
}

}  // namespace

struct StageEngine {
  StageViewport viewport{1, 1, 1.0f};
  StageCamera camera = DefaultCamera();
  StageOrbitCamera orbit_camera = DefaultOrbitCamera();
  StageEnvironment environment = DefaultEnvironment();
  std::unordered_map<int32_t, StageLight> lights;
  std::unordered_map<int32_t, ModelAssetState> model_assets;
  std::unordered_map<int32_t, ModelInstanceState> model_instances;
};

StageEngine* stage_engine_create(void) {
  return new (std::nothrow) StageEngine();
}

void stage_engine_destroy(StageEngine* engine) {
  delete engine;
}

void stage_engine_set_viewport(StageEngine* engine, StageViewport viewport) {
  if (engine == nullptr) {
    return;
  }
  engine->viewport.width = std::max(viewport.width, uint32_t{1});
  engine->viewport.height = std::max(viewport.height, uint32_t{1});
  engine->viewport.pixel_ratio = std::max(viewport.pixel_ratio, 0.1f);
}

StageViewport stage_engine_get_viewport(const StageEngine* engine) {
  return engine == nullptr ? StageViewport{1, 1, 1.0f} : engine->viewport;
}

void stage_engine_set_camera(StageEngine* engine, StageCamera camera) {
  if (engine == nullptr) {
    return;
  }
  camera.vertical_fov_degrees =
      std::clamp(camera.vertical_fov_degrees, 1.0f, 179.0f);
  camera.near_plane = std::max(camera.near_plane, 0.001f);
  camera.far_plane = std::max(camera.far_plane, camera.near_plane + 0.001f);
  engine->camera = camera;
}

StageCamera stage_engine_get_camera(const StageEngine* engine) {
  return engine == nullptr ? DefaultCamera() : engine->camera;
}

void stage_engine_set_orbit_camera(
    StageEngine* engine,
    StageOrbitCamera camera) {
  if (engine == nullptr) {
    return;
  }
  engine->orbit_camera = NormalizeOrbitCamera(camera);
  engine->camera = CameraFromOrbit(engine->orbit_camera);
}

StageOrbitCamera stage_engine_get_orbit_camera(const StageEngine* engine) {
  return engine == nullptr ? DefaultOrbitCamera() : engine->orbit_camera;
}

void stage_engine_orbit_camera(
    StageEngine* engine,
    float delta_yaw,
    float delta_pitch) {
  if (engine == nullptr) {
    return;
  }
  StageOrbitCamera camera = engine->orbit_camera;
  camera.yaw += delta_yaw;
  camera.pitch += delta_pitch;
  stage_engine_set_orbit_camera(engine, camera);
}

void stage_engine_move_camera(
    StageEngine* engine,
    float delta_x,
    float delta_y) {
  if (engine == nullptr) {
    return;
  }
  const float right = delta_x * 0.004f;
  const float forward = delta_y * 0.004f;
  StageOrbitCamera camera = engine->orbit_camera;
  const float yaw_cos = std::cos(camera.yaw);
  const float yaw_sin = std::sin(camera.yaw);
  camera.target_x += yaw_cos * right + yaw_sin * forward;
  camera.target_z += -yaw_sin * right + yaw_cos * forward;
  stage_engine_set_orbit_camera(engine, camera);
}

void stage_engine_reset_camera(StageEngine* engine) {
  stage_engine_set_orbit_camera(engine, DefaultOrbitCamera());
}

void stage_engine_set_environment(
    StageEngine* engine,
    StageEnvironment environment) {
  if (engine == nullptr) {
    return;
  }
  environment.sky_a = std::clamp(environment.sky_a, 0.0f, 1.0f);
  environment.ambient_intensity = std::max(environment.ambient_intensity, 0.0f);
  environment.reflection_intensity =
      std::clamp(environment.reflection_intensity, 0.0f, 1.0f);
  engine->environment = environment;
}

StageEnvironment stage_engine_get_environment(const StageEngine* engine) {
  return engine == nullptr ? DefaultEnvironment() : engine->environment;
}

void stage_engine_upsert_light(StageEngine* engine, StageLight light) {
  if (engine == nullptr) {
    return;
  }
  engine->lights[light.id] = NormalizeLight(light);
}

uint8_t stage_engine_get_light(
    const StageEngine* engine,
    int32_t id,
    StageLight* out_light) {
  if (engine == nullptr || out_light == nullptr) {
    return 0;
  }
  const auto found = engine->lights.find(id);
  if (found == engine->lights.end()) {
    return 0;
  }
  *out_light = found->second;
  return 1;
}

void stage_engine_set_light_position(
    StageEngine* engine,
    int32_t id,
    float x,
    float y,
    float z) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->lights.find(id);
  if (found == engine->lights.end()) {
    return;
  }
  found->second.position_x = x;
  found->second.position_y = y;
  found->second.position_z = z;
}

void stage_engine_set_light_direction(
    StageEngine* engine,
    int32_t id,
    float x,
    float y,
    float z) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->lights.find(id);
  if (found == engine->lights.end()) {
    return;
  }
  found->second.direction_x = x;
  found->second.direction_y = y;
  found->second.direction_z = z;
}

void stage_engine_set_light_intensity(
    StageEngine* engine,
    int32_t id,
    float intensity) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->lights.find(id);
  if (found == engine->lights.end()) {
    return;
  }
  found->second.intensity = std::max(intensity, 0.0f);
}

void stage_engine_remove_light(StageEngine* engine, int32_t id) {
  if (engine == nullptr) {
    return;
  }
  engine->lights.erase(id);
}

uint32_t stage_engine_light_count(const StageEngine* engine) {
  return engine == nullptr
             ? 0
             : static_cast<uint32_t>(engine->lights.size());
}

void stage_engine_register_model_asset(
    StageEngine* engine,
    int32_t asset_id,
    float normalized_scale,
    int32_t vertical_anchor,
    StageModelBounds bounds) {
  if (engine == nullptr) {
    return;
  }
  engine->model_assets[asset_id] = ModelAssetState{
      std::max(normalized_scale, 0.000001f),
      NormalizeVerticalAnchor(vertical_anchor),
      bounds,
  };
}

uint8_t stage_engine_has_model_asset(
    const StageEngine* engine,
    int32_t asset_id) {
  return engine != nullptr &&
                 engine->model_assets.find(asset_id) != engine->model_assets.end()
             ? 1
             : 0;
}

uint8_t stage_engine_remove_model_asset(
    StageEngine* engine,
    int32_t asset_id) {
  if (engine == nullptr) {
    return 0;
  }
  for (const auto& instance : engine->model_instances) {
    if (instance.second.asset_id == asset_id) {
      return 0;
    }
  }
  return engine->model_assets.erase(asset_id) > 0 ? 1 : 0;
}

uint8_t stage_engine_create_model_instance(
    StageEngine* engine,
    int32_t instance_id,
    int32_t asset_id) {
  if (engine == nullptr ||
      engine->model_assets.find(asset_id) == engine->model_assets.end()) {
    return 0;
  }
  engine->model_instances[instance_id] = ModelInstanceState{asset_id};
  return 1;
}

void stage_engine_set_model_transform(
    StageEngine* engine,
    int32_t instance_id,
    StageModelTransform transform) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->model_instances.find(instance_id);
  if (found == engine->model_instances.end()) {
    return;
  }
  found->second.transform = transform;
}

uint8_t stage_engine_get_model_matrix(
    const StageEngine* engine,
    int32_t instance_id,
    float* out_matrix_16) {
  if (engine == nullptr || out_matrix_16 == nullptr) {
    return 0;
  }
  const auto instance = engine->model_instances.find(instance_id);
  if (instance == engine->model_instances.end()) {
    return 0;
  }
  const auto asset = engine->model_assets.find(instance->second.asset_id);
  if (asset == engine->model_assets.end()) {
    return 0;
  }
  BuildModelMatrix(asset->second, instance->second.transform, out_matrix_16);
  return 1;
}

void stage_engine_remove_model_instance(
    StageEngine* engine,
    int32_t instance_id) {
  if (engine == nullptr) {
    return;
  }
  engine->model_instances.erase(instance_id);
}

uint32_t stage_engine_model_asset_count(const StageEngine* engine) {
  return engine == nullptr
             ? 0
             : static_cast<uint32_t>(engine->model_assets.size());
}

uint32_t stage_engine_model_instance_count(const StageEngine* engine) {
  return engine == nullptr
             ? 0
             : static_cast<uint32_t>(engine->model_instances.size());
}

void stage_engine_play_model_animation(
    StageEngine* engine,
    int32_t instance_id,
    int32_t animation_index,
    uint8_t loop,
    float speed,
    int64_t now_nanos,
    uint8_t paused) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->model_instances.find(instance_id);
  if (found == engine->model_instances.end()) {
    return;
  }
  found->second.has_animation = true;
  found->second.animation = ModelInstanceState::AnimationState{
      std::max(animation_index, 0),
      loop != 0,
      std::max(speed, 0.000001f),
      now_nanos,
      now_nanos,
      paused != 0,
  };
}

void stage_engine_pause_model_animation(
    StageEngine* engine,
    int32_t instance_id,
    int64_t now_nanos) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->model_instances.find(instance_id);
  if (found == engine->model_instances.end() ||
      !found->second.has_animation ||
      found->second.animation.paused) {
    return;
  }
  found->second.animation.paused_at_nanos = now_nanos;
  found->second.animation.paused = true;
}

void stage_engine_resume_model_animation(
    StageEngine* engine,
    int32_t instance_id,
    int64_t now_nanos) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->model_instances.find(instance_id);
  if (found == engine->model_instances.end() ||
      !found->second.has_animation ||
      !found->second.animation.paused) {
    return;
  }
  found->second.animation.started_at_nanos +=
      now_nanos - found->second.animation.paused_at_nanos;
  found->second.animation.paused = false;
}

void stage_engine_stop_model_animation(
    StageEngine* engine,
    int32_t instance_id) {
  if (engine == nullptr) {
    return;
  }
  const auto found = engine->model_instances.find(instance_id);
  if (found == engine->model_instances.end()) {
    return;
  }
  found->second.has_animation = false;
}

int32_t stage_engine_get_model_animation_index(
    const StageEngine* engine,
    int32_t instance_id) {
  if (engine == nullptr) {
    return -1;
  }
  const auto found = engine->model_instances.find(instance_id);
  return found == engine->model_instances.end() ||
                 !found->second.has_animation
             ? -1
             : found->second.animation.animation_index;
}

uint8_t stage_engine_sample_model_animation(
    const StageEngine* engine,
    int32_t instance_id,
    int64_t frame_time_nanos,
    float duration_seconds,
    int32_t* out_animation_index,
    float* out_animation_time) {
  if (engine == nullptr ||
      duration_seconds <= 0.0f ||
      out_animation_index == nullptr ||
      out_animation_time == nullptr) {
    return 0;
  }
  const auto found = engine->model_instances.find(instance_id);
  if (found == engine->model_instances.end() ||
      !found->second.has_animation) {
    return 0;
  }
  const auto& animation = found->second.animation;
  const int64_t sample_nanos =
      animation.paused ? animation.paused_at_nanos : frame_time_nanos;
  const double elapsed_seconds =
      static_cast<double>(sample_nanos - animation.started_at_nanos) /
      1000000000.0 * animation.speed;
  const float elapsed =
      static_cast<float>(std::max(elapsed_seconds, 0.0));
  *out_animation_index = animation.animation_index;
  *out_animation_time =
      animation.loop ? std::fmod(elapsed, duration_seconds)
                     : std::min(elapsed, duration_seconds);
  return 1;
}

uint32_t stage_engine_abi_version(void) {
  return kStageEngineAbiVersion;
}
