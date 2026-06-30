#include "stage_windows_renderer_bridge.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <optional>
#include <vector>
#include <windows.h>

#include "stage_3d/stage_engine.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableMap* ArgumentsMap(
    const flutter::MethodCall<EncodableValue>& call) {
  const auto* arguments = call.arguments();
  if (arguments == nullptr ||
      !std::holds_alternative<EncodableMap>(*arguments)) {
    return nullptr;
  }
  return &std::get<EncodableMap>(*arguments);
}

const EncodableValue* FindValue(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::optional<EncodableMap> MapValue(
    const EncodableMap& map,
    const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || !std::holds_alternative<EncodableMap>(*value)) {
    return std::nullopt;
  }
  return std::get<EncodableMap>(*value);
}

int32_t IntValue(const EncodableMap& map, const char* key, int32_t fallback = 0) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  const auto number = value->TryGetLongValue();
  return number.has_value() ? static_cast<int32_t>(*number) : fallback;
}

float FloatValue(const EncodableMap& map, const char* key, float fallback = 0) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (std::holds_alternative<double>(*value)) {
    return static_cast<float>(std::get<double>(*value));
  }
  const auto number = value->TryGetLongValue();
  return number.has_value() ? static_cast<float>(*number) : fallback;
}

bool BoolValue(
    const EncodableMap& map,
    const char* key,
    bool fallback = false) {
  const auto* value = FindValue(map, key);
  return value != nullptr && std::holds_alternative<bool>(*value)
             ? std::get<bool>(*value)
             : fallback;
}

std::string StringValue(
    const EncodableMap& map,
    const char* key,
    std::string fallback = "") {
  const auto* value = FindValue(map, key);
  return value != nullptr && std::holds_alternative<std::string>(*value)
             ? std::get<std::string>(*value)
             : fallback;
}

int32_t VerticalAnchorValue(const std::string& value) {
  if (value == "origin") {
    return STAGE_MODEL_ANCHOR_ORIGIN;
  }
  if (value == "bottom") {
    return STAGE_MODEL_ANCHOR_BOTTOM;
  }
  return STAGE_MODEL_ANCHOR_CENTER;
}

std::wstring WidenAscii(const std::string& value) {
  return std::wstring(value.begin(), value.end());
}

std::filesystem::path ExecutableDirectory() {
  std::wstring buffer(MAX_PATH, L'\0');
  const DWORD size = GetModuleFileNameW(
      nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  buffer.resize(size);
  return std::filesystem::path(buffer).parent_path();
}

void Success(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  result->Success();
}

void Error(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result,
    const std::string& message) {
  result->Error("stage_3d_windows", message);
}

StageModelTransform TransformFromMessage(const EncodableMap& map) {
  return StageModelTransform{
      FloatValue(map, "x"),
      FloatValue(map, "y"),
      FloatValue(map, "z"),
      FloatValue(map, "qx"),
      FloatValue(map, "qy"),
      FloatValue(map, "qz"),
      FloatValue(map, "qw", 1.0f),
  };
}

StageOrbitCamera OrbitCameraFromMessage(const EncodableMap& map) {
  return StageOrbitCamera{
      FloatValue(map, "targetX"),
      FloatValue(map, "targetY"),
      FloatValue(map, "targetZ"),
      FloatValue(map, "yaw"),
      FloatValue(map, "pitch"),
      FloatValue(map, "distance", 4.0f),
  };
}

StageEnvironment EnvironmentFromMessage(const EncodableMap& map) {
  return StageEnvironment{
      FloatValue(map, "skyR", 0.16f),
      FloatValue(map, "skyG", 0.48f),
      FloatValue(map, "skyB", 0.78f),
      FloatValue(map, "skyA", 1.0f),
      FloatValue(map, "ambientIntensity", 30000.0f),
      FloatValue(map, "reflectionIntensity", 0.9f),
  };
}

int32_t QualityValue(const std::string& value) {
  if (value == "medium") {
    return 1;
  }
  if (value == "high") {
    return 2;
  }
  if (value == "ultra") {
    return 3;
  }
  return 0;
}

int32_t ShadowTypeValue(const std::string& value) {
  if (value == "vsm") {
    return 1;
  }
  if (value == "dpcf") {
    return 2;
  }
  if (value == "pcss") {
    return 3;
  }
  return 0;
}

stage_3d::StageFilamentRenderer::RenderOptions RenderOptionsFromMessage(
    const EncodableMap& map) {
  stage_3d::StageFilamentRenderer::RenderOptions options;
  options.post_processing = BoolValue(map, "postProcessing", true);
  options.shadows = BoolValue(map, "shadows", true);
  options.shadow_type = ShadowTypeValue(StringValue(map, "shadowType"));

  if (const auto ao = MapValue(map, "ambientOcclusion"); ao.has_value()) {
    options.ambient_occlusion = BoolValue(*ao, "enabled");
    options.ambient_occlusion_radius = FloatValue(*ao, "radius", 0.3f);
    options.ambient_occlusion_intensity = FloatValue(*ao, "intensity", 1.0f);
    options.ambient_occlusion_power = FloatValue(*ao, "power", 1.0f);
    options.ambient_occlusion_quality =
        QualityValue(StringValue(*ao, "quality"));
  }
  if (const auto bloom = MapValue(map, "bloom"); bloom.has_value()) {
    options.bloom = BoolValue(*bloom, "enabled");
    options.bloom_strength = FloatValue(*bloom, "strength", 0.1f);
    options.bloom_resolution =
        static_cast<uint32_t>(IntValue(*bloom, "resolution", 384));
    options.bloom_levels =
        static_cast<uint8_t>(IntValue(*bloom, "levels", 6));
    options.bloom_threshold = BoolValue(*bloom, "threshold", true);
    options.bloom_quality = QualityValue(StringValue(*bloom, "quality"));
  }
  if (const auto ssr = MapValue(map, "screenSpaceReflections");
      ssr.has_value()) {
    options.screen_space_reflections = BoolValue(*ssr, "enabled");
    options.ssr_thickness = FloatValue(*ssr, "thickness", 0.1f);
    options.ssr_bias = FloatValue(*ssr, "bias", 0.01f);
    options.ssr_max_distance = FloatValue(*ssr, "maxDistance", 3.0f);
    options.ssr_stride = FloatValue(*ssr, "stride", 2.0f);
  }
  if (const auto msaa = MapValue(map, "msaa"); msaa.has_value()) {
    options.msaa = BoolValue(*msaa, "enabled");
    options.msaa_sample_count =
        static_cast<uint8_t>(IntValue(*msaa, "sampleCount", 4));
  }
  return options;
}

StageLight LightFromMessage(const EncodableMap& map) {
  return StageLight{
      IntValue(map, "id"),
      IntValue(map, "type"),
      FloatValue(map, "r", 1.0f),
      FloatValue(map, "g", 1.0f),
      FloatValue(map, "b", 1.0f),
      FloatValue(map, "intensity", 1000.0f),
      FloatValue(map, "x"),
      FloatValue(map, "y"),
      FloatValue(map, "z"),
      FloatValue(map, "dx", 0.0f),
      FloatValue(map, "dy", -1.0f),
      FloatValue(map, "dz", 0.0f),
      FloatValue(map, "falloffRadius", 10.0f),
      BoolValue(map, "castShadows", true) ? uint8_t{1} : uint8_t{0},
  };
}

void TangentFrameFromNormal(float nx, float ny, float nz, float out[4]) {
  const float length = std::sqrt(nx * nx + ny * ny + nz * nz);
  if (length <= 0.000001f) {
    out[0] = 0.0f;
    out[1] = 0.0f;
    out[2] = 0.0f;
    out[3] = 1.0f;
    return;
  }
  nx /= length;
  ny /= length;
  nz /= length;
  if (nz > 0.999999f) {
    out[0] = 0.0f;
    out[1] = 0.0f;
    out[2] = 0.0f;
    out[3] = 1.0f;
    return;
  }
  if (nz < -0.999999f) {
    out[0] = 1.0f;
    out[1] = 0.0f;
    out[2] = 0.0f;
    out[3] = 0.0f;
    return;
  }
  const float qx = -ny;
  const float qy = nx;
  const float qz = 0.0f;
  const float qw = 1.0f + nz;
  const float q_length =
      std::sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
  out[0] = qx / q_length;
  out[1] = qy / q_length;
  out[2] = qz / q_length;
  out[3] = qw / q_length;
}

std::vector<stage_3d::StageFilamentRenderer::MeshVertex> MeshVerticesFromMessage(
    const EncodableMap& map) {
  std::vector<stage_3d::StageFilamentRenderer::MeshVertex> vertices;
  const auto* value = FindValue(map, "vertices");
  if (value == nullptr || !std::holds_alternative<EncodableList>(*value)) {
    return vertices;
  }
  const auto& items = std::get<EncodableList>(*value);
  vertices.reserve(items.size());
  for (const auto& item : items) {
    if (!std::holds_alternative<EncodableMap>(item)) {
      continue;
    }
    const auto& vertex = std::get<EncodableMap>(item);
    stage_3d::StageFilamentRenderer::MeshVertex mesh_vertex{
        {FloatValue(vertex, "x"), FloatValue(vertex, "y"), FloatValue(vertex, "z")},
        {FloatValue(vertex, "u"), FloatValue(vertex, "v")},
    };
    TangentFrameFromNormal(
        FloatValue(vertex, "nx", 0.0f),
        FloatValue(vertex, "ny", 1.0f),
        FloatValue(vertex, "nz", 0.0f),
        mesh_vertex.tangent);
    vertices.push_back(mesh_vertex);
  }
  return vertices;
}

std::vector<uint32_t> MeshIndicesFromMessage(const EncodableMap& map) {
  std::vector<uint32_t> indices;
  const auto* value = FindValue(map, "indices");
  if (value == nullptr || !std::holds_alternative<EncodableList>(*value)) {
    return indices;
  }
  const auto& items = std::get<EncodableList>(*value);
  indices.reserve(items.size());
  for (const auto& item : items) {
    const auto number = item.TryGetLongValue();
    if (number.has_value() && *number >= 0) {
      indices.push_back(static_cast<uint32_t>(*number));
    }
  }
  return indices;
}

void ColorFromArgb(int32_t argb, float out_color[4]) {
  const uint32_t value = static_cast<uint32_t>(argb);
  out_color[0] = static_cast<float>((value >> 16) & 0xff) / 255.0f;
  out_color[1] = static_cast<float>((value >> 8) & 0xff) / 255.0f;
  out_color[2] = static_cast<float>(value & 0xff) / 255.0f;
  out_color[3] = static_cast<float>((value >> 24) & 0xff) / 255.0f;
}


int64_t NowNanos() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

}  // namespace

StageWindowsRendererBridge::StageWindowsRendererBridge(
    flutter::BinaryMessenger* messenger,
    std::wstring assets_path,
    stage_3d::StageFilamentRenderer* renderer)
    : assets_path_(std::move(assets_path)), renderer_(renderer) {
  std::filesystem::path normalized_assets_path(assets_path_);
  if (normalized_assets_path.is_relative()) {
    normalized_assets_path = ExecutableDirectory() / normalized_assets_path;
    assets_path_ = normalized_assets_path.wstring();
  }
  engine_ = stage_engine_create();
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger,
      "filament_view_0",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

StageWindowsRendererBridge::~StageWindowsRendererBridge() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
  stage_engine_destroy(engine_);
}

void StageWindowsRendererBridge::TickAnimations() {
  if (renderer_ == nullptr || engine_ == nullptr) {
    return;
  }
  const int64_t now_nanos = NowNanos();
  for (int32_t instance_id : animated_instances_) {
    const int32_t animation_index =
        stage_engine_get_model_animation_index(engine_, instance_id);
    if (animation_index < 0) {
      continue;
    }
    float duration_seconds = 0.0f;
    if (!renderer_->GetModelAnimationDuration(
            instance_id, animation_index, &duration_seconds)) {
      continue;
    }
    int32_t sampled_index = -1;
    float animation_time = 0.0f;
    if (stage_engine_sample_model_animation(
            engine_, instance_id, now_nanos, duration_seconds, &sampled_index,
            &animation_time) == 0) {
      continue;
    }
    renderer_->ApplyModelAnimationFrame(
        instance_id, sampled_index, animation_time);
  }
}

void StageWindowsRendererBridge::ApplyCamera() {
  if (renderer_ == nullptr || engine_ == nullptr) {
    return;
  }
  renderer_->SetCamera(stage_engine_get_camera(engine_));
}

void StageWindowsRendererBridge::OrbitCamera(
    float delta_yaw,
    float delta_pitch) {
  stage_engine_orbit_camera(engine_, delta_yaw, delta_pitch);
  ApplyCamera();
}

void StageWindowsRendererBridge::MoveCamera(float delta_x, float delta_y) {
  stage_engine_move_camera(engine_, delta_x, delta_y);
  ApplyCamera();
}

void StageWindowsRendererBridge::ZoomCamera(float wheel_delta) {
  StageOrbitCamera camera = stage_engine_get_orbit_camera(engine_);
  const float scale = wheel_delta > 0.0f ? 0.9f : 1.1f;
  camera.distance *= scale;
  stage_engine_set_orbit_camera(engine_, camera);
  ApplyCamera();
}

void StageWindowsRendererBridge::ResetCamera() {
  stage_engine_reset_camera(engine_);
  ApplyCamera();
}

void StageWindowsRendererBridge::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableMap* arguments = ArgumentsMap(call);

  if (method == "resetView") {
    ResetCamera();
    Success(std::move(result));
    return;
  }

  if (method == "setCamera") {
    if (arguments == nullptr) {
      Error(std::move(result), "setCamera expects a map.");
      return;
    }
    stage_engine_set_orbit_camera(engine_, OrbitCameraFromMessage(*arguments));
    ApplyCamera();
    Success(std::move(result));
    return;
  }

  if (method == "orbitCamera") {
    if (arguments == nullptr) {
      Error(std::move(result), "orbitCamera expects a map.");
      return;
    }
    OrbitCamera(
        FloatValue(*arguments, "deltaYaw"),
        FloatValue(*arguments, "deltaPitch"));
    Success(std::move(result));
    return;
  }

  if (method == "moveCamera") {
    if (arguments == nullptr) {
      Error(std::move(result), "moveCamera expects a map.");
      return;
    }
    MoveCamera(
        FloatValue(*arguments, "deltaX"),
        FloatValue(*arguments, "deltaY"));
    Success(std::move(result));
    return;
  }

  if (method == "setEnvironment") {
    if (arguments == nullptr) {
      Error(std::move(result), "setEnvironment expects a map.");
      return;
    }
    const StageEnvironment environment = EnvironmentFromMessage(*arguments);
    stage_engine_set_environment(engine_, environment);
    if (renderer_ != nullptr) {
      renderer_->SetEnvironment(stage_engine_get_environment(engine_));
    }
    Success(std::move(result));
    return;
  }

  if (method == "setRenderOptions") {
    if (arguments == nullptr) {
      Error(std::move(result), "setRenderOptions expects a map.");
      return;
    }
    if (renderer_ != nullptr) {
      renderer_->SetRenderOptions(RenderOptionsFromMessage(*arguments));
    }
    Success(std::move(result));
    return;
  }

  if (method == "createLight") {
    if (arguments == nullptr) {
      Error(std::move(result), "createLight expects a map.");
      return;
    }
    StageLight light = LightFromMessage(*arguments);
    stage_engine_upsert_light(engine_, light);
    if (renderer_ != nullptr &&
        stage_engine_get_light(engine_, light.id, &light) != 0) {
      renderer_->UpsertLight(light);
    }
    Success(std::move(result));
    return;
  }

  if (method == "setLightPosition") {
    if (arguments == nullptr) {
      Error(std::move(result), "setLightPosition expects a map.");
      return;
    }
    const int32_t id = IntValue(*arguments, "id");
    const float x = FloatValue(*arguments, "x");
    const float y = FloatValue(*arguments, "y");
    const float z = FloatValue(*arguments, "z");
    stage_engine_set_light_position(engine_, id, x, y, z);
    if (renderer_ != nullptr) {
      renderer_->SetLightPosition(id, x, y, z);
    }
    Success(std::move(result));
    return;
  }

  if (method == "setLightDirection") {
    if (arguments == nullptr) {
      Error(std::move(result), "setLightDirection expects a map.");
      return;
    }
    const int32_t id = IntValue(*arguments, "id");
    const float x = FloatValue(*arguments, "x");
    const float y = FloatValue(*arguments, "y");
    const float z = FloatValue(*arguments, "z");
    stage_engine_set_light_direction(engine_, id, x, y, z);
    if (renderer_ != nullptr) {
      renderer_->SetLightDirection(id, x, y, z);
    }
    Success(std::move(result));
    return;
  }

  if (method == "setLightIntensity") {
    if (arguments == nullptr) {
      Error(std::move(result), "setLightIntensity expects a map.");
      return;
    }
    const int32_t id = IntValue(*arguments, "id");
    const float intensity = FloatValue(*arguments, "intensity");
    stage_engine_set_light_intensity(engine_, id, intensity);
    if (renderer_ != nullptr) {
      renderer_->SetLightIntensity(id, intensity);
    }
    Success(std::move(result));
    return;
  }

  if (method == "destroyLight") {
    if (arguments != nullptr) {
      const int32_t id = IntValue(*arguments, "id");
      stage_engine_remove_light(engine_, id);
      if (renderer_ != nullptr) {
        renderer_->RemoveLight(id);
      }
    }
    Success(std::move(result));
    return;
  }

  if (method == "createTexturedMesh") {
    if (arguments == nullptr) {
      Error(std::move(result), "createTexturedMesh expects a map.");
      return;
    }
    const int32_t mesh_id = IntValue(*arguments, "meshId");
    if (renderer_ != nullptr &&
        !renderer_->CreateTexturedMesh(
            mesh_id,
            MeshVerticesFromMessage(*arguments),
            MeshIndicesFromMessage(*arguments),
            MeshMaterialFromMessage(*arguments))) {
      Error(std::move(result), "Filament failed to create textured mesh.");
      return;
    }
    Success(std::move(result));
    return;
  }

  if (method == "destroyTexturedMesh") {
    if (arguments != nullptr && renderer_ != nullptr) {
      renderer_->DestroyTexturedMesh(IntValue(*arguments, "meshId"));
    }
    Success(std::move(result));
    return;
  }

  if (method == "loadModelAsset") {
    if (arguments == nullptr) {
      Error(std::move(result), "loadModelAsset expects a map.");
      return;
    }
    const int32_t asset_id = IntValue(*arguments, "assetId");
    const std::string asset_path = StringValue(*arguments, "assetPath");
    std::vector<uint8_t> bytes;
    if (!ReadAssetBytes(asset_path, &bytes)) {
      Error(std::move(result), "Could not read Flutter asset: " + asset_path);
      return;
    }
    if (renderer_ == nullptr || !renderer_->IsInitialized()) {
      Success(std::move(result));
      return;
    }
    stage_3d::StageFilamentRenderer::ModelBounds renderer_bounds;
    if (!renderer_->LoadModelAssetFromMemory(
            asset_id, bytes.data(), static_cast<uint32_t>(bytes.size()),
            &renderer_bounds)) {
      const std::string details = renderer_->LastError().empty()
                                      ? "unknown renderer error"
                                      : renderer_->LastError();
      Error(
          std::move(result),
          "Filament failed to load asset: " + asset_path + " (" + details +
              ")");
      return;
    }
    stage_engine_register_model_asset(
        engine_,
        asset_id,
        FloatValue(*arguments, "normalizedScale", 1.0f),
        VerticalAnchorValue(StringValue(*arguments, "verticalAnchor")),
        StageModelBounds{
            renderer_bounds.center[0],
            renderer_bounds.center[1],
            renderer_bounds.center[2],
            renderer_bounds.half_extent[0],
            renderer_bounds.half_extent[1],
            renderer_bounds.half_extent[2],
        });
    Success(std::move(result));
    return;
  }

  if (method == "unloadModelAsset") {
    if (arguments == nullptr) {
      Error(std::move(result), "unloadModelAsset expects a map.");
      return;
    }
    const int32_t asset_id = IntValue(*arguments, "assetId");
    stage_engine_remove_model_asset(engine_, asset_id);
    if (renderer_ != nullptr) {
      renderer_->UnloadModelAsset(asset_id);
    }
    Success(std::move(result));
    return;
  }

  if (method == "createModelInstance") {
    if (arguments == nullptr) {
      Error(std::move(result), "createModelInstance expects a map.");
      return;
    }
    const int32_t instance_id = IntValue(*arguments, "instanceId");
    const int32_t asset_id = IntValue(*arguments, "assetId");
    stage_engine_remove_model_instance(engine_, instance_id);
    if (renderer_ != nullptr) {
      renderer_->DestroyModelInstance(instance_id);
    }
    if (!stage_engine_create_model_instance(engine_, instance_id, asset_id)) {
      Error(std::move(result), "Unknown model asset.");
      return;
    }
    if (renderer_ != nullptr &&
        !renderer_->CreateModelInstance(instance_id, asset_id)) {
      stage_engine_remove_model_instance(engine_, instance_id);
      Error(std::move(result), "Filament failed to create model instance.");
      return;
    }
    stage_engine_set_model_transform(
        engine_, instance_id, TransformFromMessage(*arguments));
    float matrix[16];
    if (renderer_ != nullptr &&
        stage_engine_get_model_matrix(engine_, instance_id, matrix) != 0) {
      renderer_->SetModelTransform(instance_id, matrix);
    }
    if (const auto* animation = FindValue(*arguments, "animationIndex");
        animation != nullptr && animation->TryGetLongValue().has_value()) {
      stage_engine_play_model_animation(
          engine_,
          instance_id,
          static_cast<int32_t>(*animation->TryGetLongValue()),
          BoolValue(*arguments, "loop", true) ? 1 : 0,
          FloatValue(*arguments, "speed", 1.0f),
          NowNanos(),
          BoolValue(*arguments, "paused") ? 1 : 0);
      animated_instances_.insert(instance_id);
    }
    Success(std::move(result));
    return;
  }

  if (method == "setModelTransform") {
    if (arguments == nullptr) {
      Error(std::move(result), "setModelTransform expects a map.");
      return;
    }
    const int32_t instance_id = IntValue(*arguments, "instanceId");
    stage_engine_set_model_transform(
        engine_, instance_id, TransformFromMessage(*arguments));
    float matrix[16];
    if (renderer_ != nullptr &&
        stage_engine_get_model_matrix(engine_, instance_id, matrix) != 0) {
      renderer_->SetModelTransform(instance_id, matrix);
    }
    Success(std::move(result));
    return;
  }

  if (method == "destroyModelInstance") {
    if (arguments != nullptr) {
      const int32_t instance_id = IntValue(*arguments, "instanceId");
      animated_instances_.erase(instance_id);
      stage_engine_remove_model_instance(engine_, instance_id);
      if (renderer_ != nullptr) {
        renderer_->DestroyModelInstance(instance_id);
      }
    }
    Success(std::move(result));
    return;
  }

  if (method == "getModelAnimations") {
    if (arguments == nullptr || renderer_ == nullptr) {
      result->Success(EncodableValue(EncodableList{}));
      return;
    }
    const int32_t instance_id = IntValue(*arguments, "instanceId");
    EncodableList animations;
    for (const auto& animation : renderer_->GetModelAnimations(instance_id)) {
      animations.push_back(EncodableValue(EncodableMap{
          {EncodableValue("index"), EncodableValue(animation.index)},
          {EncodableValue("name"), EncodableValue(animation.name)},
          {EncodableValue("durationSeconds"),
           EncodableValue(static_cast<double>(animation.duration_seconds))},
      }));
    }
    result->Success(EncodableValue(animations));
    return;
  }

  if (method == "playModelAnimation") {
    if (arguments == nullptr) {
      Error(std::move(result), "playModelAnimation expects a map.");
      return;
    }
    stage_engine_play_model_animation(
        engine_,
        IntValue(*arguments, "instanceId"),
        IntValue(*arguments, "animationIndex"),
        BoolValue(*arguments, "loop", true) ? 1 : 0,
        FloatValue(*arguments, "speed", 1.0f),
        NowNanos(),
        BoolValue(*arguments, "paused") ? 1 : 0);
    animated_instances_.insert(IntValue(*arguments, "instanceId"));
    Success(std::move(result));
    return;
  }

  if (method == "pauseModelAnimation") {
    if (arguments != nullptr) {
      stage_engine_pause_model_animation(
          engine_, IntValue(*arguments, "instanceId"), NowNanos());
    }
    Success(std::move(result));
    return;
  }

  if (method == "resumeModelAnimation") {
    if (arguments != nullptr) {
      stage_engine_resume_model_animation(
          engine_, IntValue(*arguments, "instanceId"), NowNanos());
    }
    Success(std::move(result));
    return;
  }

  if (method == "stopModelAnimation") {
    if (arguments != nullptr) {
      stage_engine_stop_model_animation(engine_, IntValue(*arguments, "instanceId"));
      animated_instances_.erase(IntValue(*arguments, "instanceId"));
    }
    Success(std::move(result));
    return;
  }

  result->NotImplemented();
}

std::wstring StageWindowsRendererBridge::ResolveAssetPath(
    const std::string& asset_path) const {
  const std::filesystem::path root(assets_path_);
  const std::vector<std::filesystem::path> candidates = {
      root / WidenAscii(asset_path),
      root / L"assets" / WidenAscii(asset_path),
      root / L"packages" / L"stage_3d" / WidenAscii(asset_path),
      root / L"packages" / L"stage_3d" / L"assets" / WidenAscii(asset_path),
  };
  for (const auto& candidate : candidates) {
    if (std::filesystem::exists(candidate)) {
      return candidate.wstring();
    }
  }
  return candidates.front().wstring();
}

stage_3d::StageFilamentRenderer::MeshMaterial
StageWindowsRendererBridge::MeshMaterialFromMessage(
    const flutter::EncodableMap& map) const {
  stage_3d::StageFilamentRenderer::MeshMaterial material;
  const auto material_map = MapValue(map, "material");
  if (!material_map.has_value()) {
    return material;
  }

  const std::string filamat_path =
      StringValue(*material_map, "filamatAssetPath");
  if (!filamat_path.empty() &&
      ReadAssetBytes(filamat_path, &material.filamat_bytes)) {
    material.cache_key = filamat_path;
  }

  ColorFromArgb(
      IntValue(*material_map, "baseColor", 0xffffffff),
      material.base_color);
  material.roughness = FloatValue(*material_map, "roughnessFactor", 0.9f);
  material.metallic = FloatValue(*material_map, "metallicFactor", 0.0f);

  std::optional<EncodableMap> texture_map = MapValue(*material_map, "texture");
  if (!texture_map.has_value()) {
    texture_map = MapValue(map, "texture");
  }
  if (texture_map.has_value()) {
    if (const auto texture = MeshTextureFromMessage(*texture_map, "albedo");
        texture.has_value()) {
      material.textures.push_back(*texture);
    }
  }
  if (const auto texture_uniforms = MapValue(*material_map, "textureUniforms");
      texture_uniforms.has_value()) {
    for (const auto& item : *texture_uniforms) {
      if (!std::holds_alternative<std::string>(item.first) ||
          !std::holds_alternative<EncodableMap>(item.second)) {
        continue;
      }
      const auto texture = MeshTextureFromMessage(
          std::get<EncodableMap>(item.second),
          std::get<std::string>(item.first));
      if (texture.has_value()) {
        material.textures.push_back(*texture);
      }
    }
  }
  const auto* shader_value = FindValue(*material_map, "shader");
  if (shader_value != nullptr &&
      std::holds_alternative<EncodableMap>(*shader_value)) {
    const auto& shader_map = std::get<EncodableMap>(*shader_value);
    const auto* uniforms_value = FindValue(shader_map, "uniforms");
    if (uniforms_value != nullptr &&
        std::holds_alternative<EncodableList>(*uniforms_value)) {
      for (const auto& item : std::get<EncodableList>(*uniforms_value)) {
        if (!std::holds_alternative<EncodableMap>(item)) {
          continue;
        }
        const auto& uniform_map = std::get<EncodableMap>(item);
        const std::string name = StringValue(uniform_map, "name");
        const std::string type = StringValue(uniform_map, "type");
        if (name.empty()) {
          continue;
        }
        stage_3d::StageFilamentRenderer::MeshUniform uniform;
        uniform.name = name;
        if (type == "bool") {
          uniform.type =
              stage_3d::StageFilamentRenderer::MeshUniform::Type::kBool;
          uniform.bool_value = BoolValue(uniform_map, "value");
        } else if (type == "color") {
          uniform.type =
              stage_3d::StageFilamentRenderer::MeshUniform::Type::kColor;
          ColorFromArgb(
              IntValue(uniform_map, "value", 0xffffffff),
              uniform.color_value);
        } else {
          uniform.type =
              stage_3d::StageFilamentRenderer::MeshUniform::Type::kFloat;
          uniform.float_value = FloatValue(uniform_map, "value");
        }
        material.uniforms.push_back(uniform);
      }
    }
  }
  return material;
}

std::optional<stage_3d::StageFilamentRenderer::MeshTexture>
StageWindowsRendererBridge::MeshTextureFromMessage(
    const flutter::EncodableMap& map,
    const std::string& uniform_name) const {
  const std::string texture_path = StringValue(map, "assetPath");
  if (texture_path.empty()) {
    return std::nullopt;
  }
  stage_3d::StageFilamentRenderer::MeshTexture texture;
  texture.uniform_name = uniform_name;
  if (!ReadAssetBytes(texture_path, &texture.bytes)) {
    return std::nullopt;
  }
  texture.cache_key = texture_path;
  if (const auto region_map = MapValue(map, "sourceRegion");
      region_map.has_value()) {
    texture.region[0] = FloatValue(*region_map, "left", 0.0f);
    texture.region[1] = FloatValue(*region_map, "top", 0.0f);
    texture.region[2] = FloatValue(*region_map, "right", 1.0f);
    texture.region[3] = FloatValue(*region_map, "bottom", 1.0f);
    texture.has_region = true;
    texture.cache_key +=
        "#" + std::to_string(texture.region[0]) +
        "," + std::to_string(texture.region[1]) +
        "," + std::to_string(texture.region[2]) +
        "," + std::to_string(texture.region[3]);
  }
  return texture;
}

bool StageWindowsRendererBridge::ReadAssetBytes(
    const std::string& asset_path,
    std::vector<uint8_t>* out_bytes) const {
  if (out_bytes == nullptr) {
    return false;
  }
  const std::wstring resolved = ResolveAssetPath(asset_path);
  std::ifstream file(resolved, std::ios::binary | std::ios::ate);
  if (!file) {
    return false;
  }
  const std::streamsize size = file.tellg();
  if (size <= 0) {
    return false;
  }
  file.seekg(0, std::ios::beg);
  out_bytes->resize(static_cast<size_t>(size));
  return file.read(reinterpret_cast<char*>(out_bytes->data()), size).good();
}
