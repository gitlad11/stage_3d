#ifndef STAGE_3D_STAGE_FILAMENT_RENDERER_H_
#define STAGE_3D_STAGE_FILAMENT_RENDERER_H_

#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include <windows.h>

#include "stage_3d/stage_engine.h"

namespace stage_3d {

class StageFilamentRenderer {
 public:
  struct ModelBounds {
    float center[3] = {0.0f, 0.0f, 0.0f};
    float half_extent[3] = {0.0f, 0.0f, 0.0f};
  };
  struct ModelAnimation {
    int32_t index = 0;
    std::string name;
    float duration_seconds = 0.0f;
  };
  struct MeshVertex {
    float position[3] = {0.0f, 0.0f, 0.0f};
    float uv[2] = {0.0f, 0.0f};
    float tangent[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  };
  struct MeshTexture {
    std::string uniform_name;
    std::string cache_key;
    std::vector<uint8_t> bytes;
    float region[4] = {0.0f, 0.0f, 1.0f, 1.0f};
    bool has_region = false;
  };
  struct MeshUniform {
    enum class Type {
      kFloat,
      kBool,
      kColor,
    };
    std::string name;
    Type type = Type::kFloat;
    float float_value = 0.0f;
    bool bool_value = false;
    float color_value[4] = {1.0f, 1.0f, 1.0f, 1.0f};
  };
  struct MeshMaterial {
    std::string cache_key;
    std::vector<uint8_t> filamat_bytes;
    std::vector<MeshTexture> textures;
    std::vector<MeshUniform> uniforms;
    float base_color[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    float roughness = 0.9f;
    float metallic = 0.0f;
  };
  struct RenderOptions {
    bool post_processing = true;
    bool shadows = true;
    int32_t shadow_type = 0;
    bool ambient_occlusion = false;
    float ambient_occlusion_radius = 0.3f;
    float ambient_occlusion_intensity = 1.0f;
    float ambient_occlusion_power = 1.0f;
    int32_t ambient_occlusion_quality = 0;
    bool bloom = false;
    float bloom_strength = 0.1f;
    uint32_t bloom_resolution = 384;
    uint8_t bloom_levels = 6;
    bool bloom_threshold = true;
    int32_t bloom_quality = 0;
    bool screen_space_reflections = false;
    float ssr_thickness = 0.1f;
    float ssr_bias = 0.01f;
    float ssr_max_distance = 3.0f;
    float ssr_stride = 2.0f;
    bool msaa = false;
    uint8_t msaa_sample_count = 4;
  };

  StageFilamentRenderer();
  ~StageFilamentRenderer();

  StageFilamentRenderer(const StageFilamentRenderer&) = delete;
  StageFilamentRenderer& operator=(const StageFilamentRenderer&) = delete;

  bool Initialize(HWND native_window, int width, int height);
  void Shutdown();
  bool IsInitialized() const;
  bool HasSurface() const;
  void Resize(int width, int height);
  void RenderFrame();
  bool SetCamera(const StageCamera& camera);
  bool SetRenderOptions(const RenderOptions& options);
  bool SetEnvironment(const StageEnvironment& environment);
  bool UpsertLight(const StageLight& light);
  bool SetLightPosition(int32_t light_id, float x, float y, float z);
  bool SetLightDirection(int32_t light_id, float x, float y, float z);
  bool SetLightIntensity(int32_t light_id, float intensity);
  void RemoveLight(int32_t light_id);
  bool CreateTexturedMesh(
      int32_t mesh_id,
      const std::vector<MeshVertex>& vertices,
      const std::vector<uint32_t>& indices,
      const MeshMaterial& material);
  void DestroyTexturedMesh(int32_t mesh_id);
  bool LoadModelAssetFromMemory(
      int32_t asset_id,
      const uint8_t* bytes,
      uint32_t byte_count,
      ModelBounds* out_bounds = nullptr);
  bool UnloadModelAsset(int32_t asset_id);
  bool CreateModelInstance(
      int32_t instance_id,
      int32_t asset_id,
      bool cast_shadows = true,
      bool receive_shadows = true);
  void DestroyModelInstance(int32_t instance_id);
  bool SetModelTransform(int32_t instance_id, const float* matrix_16);
  std::vector<ModelAnimation> GetModelAnimations(int32_t instance_id) const;
  bool GetModelAnimationDuration(
      int32_t instance_id,
      int32_t animation_index,
      float* out_duration_seconds) const;
  bool ApplyModelAnimationFrame(
      int32_t instance_id,
      int32_t animation_index,
      float animation_time_seconds);
  const std::string& LastError() const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace stage_3d

#endif  // STAGE_3D_STAGE_FILAMENT_RENDERER_H_
