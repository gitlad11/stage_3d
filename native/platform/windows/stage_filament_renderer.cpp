#include "stage_filament_renderer.h"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <cmath>
#include <sstream>
#include <unordered_map>
#include <vector>
#include <wincodec.h>
#include <wrl/client.h>

#if defined(STAGE_HAS_FILAMENT)
#include <filament/Camera.h>
#include <filament/Engine.h>
#include <filament/IndexBuffer.h>
#include <filament/LightManager.h>
#include <filament/Material.h>
#include <filament/MaterialInstance.h>
#include <filament/RenderableManager.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/SwapChain.h>
#include <filament/Texture.h>
#include <filament/TextureSampler.h>
#include <filament/TransformManager.h>
#include <filament/View.h>
#include <filament/Viewport.h>
#include <filament/VertexBuffer.h>
#include <backend/PixelBufferDescriptor.h>
#include <gltfio/Animator.h>
#include <gltfio/AssetLoader.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/FilamentInstance.h>
#include <gltfio/MaterialProvider.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/TextureProvider.h>
#include <math/mat4.h>
#include <math/vec3.h>
#include <math/vec4.h>
#include <utils/EntityManager.h>
#endif

namespace stage_3d {

class StageFilamentRenderer::Impl {
 public:
#if defined(STAGE_HAS_FILAMENT)
  filament::Engine* engine = nullptr;
  filament::Renderer* renderer = nullptr;
  filament::Scene* scene = nullptr;
  filament::SwapChain* swap_chain = nullptr;
  filament::View* view = nullptr;
  filament::Camera* camera = nullptr;
  filament::gltfio::MaterialProvider* material_provider = nullptr;
  filament::gltfio::TextureProvider* texture_provider = nullptr;
  filament::gltfio::AssetLoader* asset_loader = nullptr;
  filament::gltfio::ResourceLoader* resource_loader = nullptr;
  utils::Entity camera_entity;
  utils::Entity sun_entity;
#endif
  bool initialized = false;
  bool has_surface = false;
  int width = 0;
  int height = 0;
  StageCamera camera_state{
      0.0f, 0.0f, 4.0f,
      0.0f, 0.0f, 0.0f,
      0.0f, 1.0f, 0.0f,
      45.0f, 0.05f, 1000.0f,
  };
  std::string last_error;

#if defined(STAGE_HAS_FILAMENT)
  struct ModelAsset {
    filament::gltfio::FilamentAsset* asset = nullptr;
  };

  struct ModelInstance {
    int32_t asset_id = 0;
    filament::gltfio::FilamentInstance* instance = nullptr;
  };
  struct TexturedMesh {
    utils::Entity entity;
    filament::VertexBuffer* vertex_buffer = nullptr;
    filament::IndexBuffer* index_buffer = nullptr;
    filament::MaterialInstance* material_instance = nullptr;
  };
  struct MaterialResource {
    filament::Material* material = nullptr;
  };
  struct TextureResource {
    filament::Texture* texture = nullptr;
  };

  std::unordered_map<int32_t, utils::Entity> light_entities;
  std::unordered_map<int32_t, TexturedMesh> textured_meshes;
  std::unordered_map<int32_t, ModelAsset> model_assets;
  std::unordered_map<int32_t, ModelInstance> model_instances;
  std::unordered_map<int32_t, std::vector<filament::gltfio::FilamentInstance*>>
      pooled_model_instances;
  std::unordered_map<std::string, MaterialResource> material_cache;
  std::unordered_map<std::string, TextureResource> texture_cache;
#endif
};

#if defined(STAGE_HAS_FILAMENT)
filament::math::float3 DirectionOrFallback(
    float x,
    float y,
    float z,
    filament::math::float3 fallback) {
  const float length = std::sqrt(x * x + y * y + z * z);
  if (length <= 0.000001f) {
    return fallback;
  }
  return filament::math::float3{x / length, y / length, z / length};
}

void DeleteBuffer(void* buffer, size_t, void*) {
  delete[] static_cast<uint8_t*>(buffer);
}

filament::QualityLevel QualityFromInt(int32_t value) {
  switch (value) {
    case 1:
      return filament::QualityLevel::MEDIUM;
    case 2:
      return filament::QualityLevel::HIGH;
    case 3:
      return filament::QualityLevel::ULTRA;
    default:
      return filament::QualityLevel::LOW;
  }
}

filament::ShadowType ShadowTypeFromInt(int32_t value) {
  switch (value) {
    case 1:
      return filament::ShadowType::VSM;
    case 2:
      return filament::ShadowType::DPCF;
    case 3:
      return filament::ShadowType::PCSS;
    default:
      return filament::ShadowType::PCF;
  }
}

struct DecodedImage {
  uint32_t width = 0;
  uint32_t height = 0;
  std::vector<uint8_t> rgba;
};

bool DecodeImageWithWic(
    const uint8_t* bytes,
    size_t byte_count,
    DecodedImage* out_image) {
  if (bytes == nullptr || byte_count == 0 || out_image == nullptr) {
    return false;
  }
  const HRESULT co_init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool should_uninitialize = SUCCEEDED(co_init);
  if (FAILED(co_init) && co_init != RPC_E_CHANGED_MODE) {
    return false;
  }

  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(
      CLSID_WICImagingFactory,
      nullptr,
      CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&factory));

  Microsoft::WRL::ComPtr<IWICStream> stream;
  if (SUCCEEDED(hr)) {
    hr = factory->CreateStream(&stream);
  }
  if (SUCCEEDED(hr)) {
    hr = stream->InitializeFromMemory(
        const_cast<BYTE*>(reinterpret_cast<const BYTE*>(bytes)),
        static_cast<DWORD>(byte_count));
  }

  Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder;
  if (SUCCEEDED(hr)) {
    hr = factory->CreateDecoderFromStream(
        stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder);
  }

  Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> frame;
  if (SUCCEEDED(hr)) {
    hr = decoder->GetFrame(0, &frame);
  }

  Microsoft::WRL::ComPtr<IWICFormatConverter> converter;
  if (SUCCEEDED(hr)) {
    hr = factory->CreateFormatConverter(&converter);
  }
  if (SUCCEEDED(hr)) {
    hr = converter->Initialize(
        frame.Get(),
        GUID_WICPixelFormat32bppRGBA,
        WICBitmapDitherTypeNone,
        nullptr,
        0.0,
        WICBitmapPaletteTypeCustom);
  }

  UINT width = 0;
  UINT height = 0;
  if (SUCCEEDED(hr)) {
    hr = converter->GetSize(&width, &height);
  }
  if (SUCCEEDED(hr) && width > 0 && height > 0) {
    std::vector<uint8_t> rgba(static_cast<size_t>(width) * height * 4);
    hr = converter->CopyPixels(
        nullptr,
        width * 4,
        static_cast<UINT>(rgba.size()),
        rgba.data());
    if (SUCCEEDED(hr)) {
      out_image->width = width;
      out_image->height = height;
      out_image->rgba = std::move(rgba);
    }
  }

  if (should_uninitialize) {
    CoUninitialize();
  }
  return SUCCEEDED(hr) && out_image->width > 0 && out_image->height > 0;
}

void CropImageToRegion(
    DecodedImage* image,
    const float region[4]) {
  if (image == nullptr || image->width == 0 || image->height == 0 ||
      image->rgba.empty()) {
    return;
  }
  const uint32_t left = std::clamp(
      static_cast<uint32_t>(std::floor(region[0] * image->width)),
      uint32_t{0},
      image->width - 1);
  const uint32_t top = std::clamp(
      static_cast<uint32_t>(std::floor(region[1] * image->height)),
      uint32_t{0},
      image->height - 1);
  const uint32_t right = std::clamp(
      static_cast<uint32_t>(std::ceil(region[2] * image->width)),
      left + 1,
      image->width);
  const uint32_t bottom = std::clamp(
      static_cast<uint32_t>(std::ceil(region[3] * image->height)),
      top + 1,
      image->height);
  const uint32_t cropped_width = right - left;
  const uint32_t cropped_height = bottom - top;
  std::vector<uint8_t> cropped(
      static_cast<size_t>(cropped_width) * cropped_height * 4);
  for (uint32_t y = 0; y < cropped_height; ++y) {
    const size_t source_offset =
        (static_cast<size_t>(top + y) * image->width + left) * 4;
    const size_t target_offset = static_cast<size_t>(y) * cropped_width * 4;
    std::memcpy(
        cropped.data() + target_offset,
        image->rgba.data() + source_offset,
        static_cast<size_t>(cropped_width) * 4);
  }
  image->width = cropped_width;
  image->height = cropped_height;
  image->rgba = std::move(cropped);
}
#endif

StageFilamentRenderer::StageFilamentRenderer()
    : impl_(std::make_unique<Impl>()) {}

StageFilamentRenderer::~StageFilamentRenderer() {
  Shutdown();
}

bool StageFilamentRenderer::Initialize(HWND native_window,
                                       int width,
                                       int height) {
  if (impl_->initialized) {
    return true;
  }
  if (native_window == nullptr || width <= 0 || height <= 0) {
    return false;
  }

#if defined(STAGE_HAS_FILAMENT)
  impl_->engine = filament::Engine::create(filament::Engine::Backend::OPENGL);
  if (impl_->engine == nullptr) {
    return false;
  }

  impl_->renderer = impl_->engine->createRenderer();
  impl_->scene = impl_->engine->createScene();
  impl_->swap_chain = impl_->engine->createSwapChain(native_window);
  impl_->view = impl_->engine->createView();
  impl_->camera_entity = utils::EntityManager::get().create();
  impl_->camera = impl_->engine->createCamera(impl_->camera_entity);
  impl_->sun_entity = utils::EntityManager::get().create();
  impl_->material_provider =
      filament::gltfio::createJitShaderProvider(impl_->engine);
  filament::gltfio::AssetConfiguration asset_config{};
  asset_config.engine = impl_->engine;
  asset_config.materials = impl_->material_provider;
  asset_config.entities = &utils::EntityManager::get();
  impl_->asset_loader = filament::gltfio::AssetLoader::create(asset_config);

  filament::gltfio::ResourceConfiguration resource_config{};
  resource_config.engine = impl_->engine;
  resource_config.gltfPath = nullptr;
  resource_config.normalizeSkinningWeights = true;
  impl_->resource_loader =
      new filament::gltfio::ResourceLoader(resource_config);
  impl_->texture_provider =
      filament::gltfio::createStbProvider(impl_->engine);

  if (impl_->renderer == nullptr || impl_->scene == nullptr ||
      impl_->swap_chain == nullptr || impl_->view == nullptr ||
      impl_->camera == nullptr || impl_->material_provider == nullptr ||
      impl_->asset_loader == nullptr || impl_->resource_loader == nullptr ||
      impl_->texture_provider == nullptr) {
    Shutdown();
    return false;
  }
  impl_->resource_loader->addTextureProvider("image/png", impl_->texture_provider);
  impl_->resource_loader->addTextureProvider("image/jpeg", impl_->texture_provider);

  filament::Renderer::ClearOptions clear_options;
  clear_options.clearColor = filament::math::float4{0.035f, 0.045f, 0.055f, 1.0f};
  clear_options.clear = true;
  impl_->renderer->setClearOptions(clear_options);

  impl_->view->setScene(impl_->scene);
  impl_->view->setCamera(impl_->camera);
  filament::LightManager::Builder(filament::LightManager::Type::SUN)
      .color({1.0f, 0.97f, 0.9f})
      .intensity(110000.0f)
      .direction({-0.45f, -0.85f, -0.25f})
      .sunAngularRadius(1.9f)
      .castShadows(false)
      .build(*impl_->engine, impl_->sun_entity);
  impl_->scene->addEntity(impl_->sun_entity);
  impl_->camera->lookAt(
      filament::math::double3{0.0, 1.4, 4.0},
      filament::math::double3{0.0, 0.8, 0.0},
      filament::math::double3{0.0, 1.0, 0.0});

  impl_->initialized = true;
  impl_->has_surface = true;
  Resize(width, height);
  return true;
#else
  return false;
#endif
}

void StageFilamentRenderer::Shutdown() {
#if defined(STAGE_HAS_FILAMENT)
  if (impl_->engine != nullptr) {
    const std::vector<int32_t> instance_ids = [&]() {
      std::vector<int32_t> ids;
      ids.reserve(impl_->model_instances.size());
      for (const auto& item : impl_->model_instances) {
        ids.push_back(item.first);
      }
      return ids;
    }();
    for (int32_t id : instance_ids) {
      DestroyModelInstance(id);
    }
    const std::vector<int32_t> light_ids = [&]() {
      std::vector<int32_t> ids;
      ids.reserve(impl_->light_entities.size());
      for (const auto& item : impl_->light_entities) {
        ids.push_back(item.first);
      }
      return ids;
    }();
    for (int32_t id : light_ids) {
      RemoveLight(id);
    }
    const std::vector<int32_t> mesh_ids = [&]() {
      std::vector<int32_t> ids;
      ids.reserve(impl_->textured_meshes.size());
      for (const auto& item : impl_->textured_meshes) {
        ids.push_back(item.first);
      }
      return ids;
    }();
    for (int32_t id : mesh_ids) {
      DestroyTexturedMesh(id);
    }
    const std::vector<int32_t> asset_ids = [&]() {
      std::vector<int32_t> ids;
      ids.reserve(impl_->model_assets.size());
      for (const auto& item : impl_->model_assets) {
        ids.push_back(item.first);
      }
      return ids;
    }();
    for (int32_t id : asset_ids) {
      UnloadModelAsset(id);
    }

    for (auto& item : impl_->material_cache) {
      if (item.second.material != nullptr) {
        impl_->engine->destroy(item.second.material);
      }
    }
    impl_->material_cache.clear();
    for (auto& item : impl_->texture_cache) {
      if (item.second.texture != nullptr) {
        impl_->engine->destroy(item.second.texture);
      }
    }
    impl_->texture_cache.clear();

    delete impl_->resource_loader;
    impl_->resource_loader = nullptr;

    filament::gltfio::AssetLoader::destroy(&impl_->asset_loader);
    if (impl_->material_provider != nullptr) {
      impl_->material_provider->destroyMaterials();
      delete impl_->material_provider;
      impl_->material_provider = nullptr;
    }
    delete impl_->texture_provider;
    impl_->texture_provider = nullptr;

    if (impl_->view != nullptr) {
      impl_->engine->destroy(impl_->view);
    }
    if (impl_->swap_chain != nullptr) {
      impl_->engine->destroy(impl_->swap_chain);
    }
    if (impl_->scene != nullptr) {
      impl_->scene->remove(impl_->sun_entity);
      impl_->engine->destroy(impl_->scene);
    }
    if (impl_->camera) {
      impl_->engine->destroyCameraComponent(impl_->camera_entity);
      utils::EntityManager::get().destroy(impl_->camera_entity);
    }
    if (impl_->sun_entity) {
      impl_->engine->destroy(impl_->sun_entity);
      utils::EntityManager::get().destroy(impl_->sun_entity);
    }
    if (impl_->renderer != nullptr) {
      impl_->engine->destroy(impl_->renderer);
    }
    filament::Engine::destroy(&impl_->engine);
  }

  impl_->renderer = nullptr;
  impl_->scene = nullptr;
  impl_->swap_chain = nullptr;
  impl_->view = nullptr;
  impl_->camera = nullptr;
  impl_->asset_loader = nullptr;
#endif
  impl_->initialized = false;
  impl_->has_surface = false;
  impl_->width = 0;
  impl_->height = 0;
}

bool StageFilamentRenderer::IsInitialized() const {
  return impl_->initialized;
}

bool StageFilamentRenderer::HasSurface() const {
  return impl_->has_surface;
}

void StageFilamentRenderer::Resize(int width, int height) {
  if (width <= 0 || height <= 0) {
    return;
  }
  impl_->width = width;
  impl_->height = height;

#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->view == nullptr || impl_->camera == nullptr) {
    return;
  }
  impl_->view->setViewport(filament::Viewport{
      0,
      0,
      static_cast<uint32_t>(width),
      static_cast<uint32_t>(height),
  });
  const double aspect = static_cast<double>(width) / static_cast<double>(height);
  impl_->camera->setProjection(
      impl_->camera_state.vertical_fov_degrees,
      aspect,
      impl_->camera_state.near_plane,
      impl_->camera_state.far_plane,
      filament::Camera::Fov::VERTICAL);
#endif
}

bool StageFilamentRenderer::SetCamera(const StageCamera& camera) {
  impl_->camera_state = camera;
#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->camera == nullptr) {
    return false;
  }
  impl_->camera->lookAt(
      filament::math::double3{camera.eye_x, camera.eye_y, camera.eye_z},
      filament::math::double3{
          camera.target_x,
          camera.target_y,
          camera.target_z,
      },
      filament::math::double3{camera.up_x, camera.up_y, camera.up_z});
  Resize(impl_->width, impl_->height);
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::SetRenderOptions(const RenderOptions& options) {
#if defined(STAGE_HAS_FILAMENT)
  if (impl_->view == nullptr) {
    return false;
  }
  impl_->view->setPostProcessingEnabled(options.post_processing);
  impl_->view->setShadowingEnabled(options.shadows);
  impl_->view->setShadowType(ShadowTypeFromInt(options.shadow_type));

  filament::View::AmbientOcclusionOptions ao_options;
  ao_options.enabled = options.ambient_occlusion;
  ao_options.radius = options.ambient_occlusion_radius;
  ao_options.intensity = options.ambient_occlusion_intensity;
  ao_options.power = options.ambient_occlusion_power;
  ao_options.quality = QualityFromInt(options.ambient_occlusion_quality);
  impl_->view->setAmbientOcclusionOptions(ao_options);

  filament::View::BloomOptions bloom_options;
  bloom_options.enabled = options.bloom;
  bloom_options.strength = options.bloom_strength;
  bloom_options.resolution = options.bloom_resolution;
  bloom_options.levels = options.bloom_levels;
  bloom_options.threshold = options.bloom_threshold;
  bloom_options.quality = QualityFromInt(options.bloom_quality);
  impl_->view->setBloomOptions(bloom_options);

  filament::View::ScreenSpaceReflectionsOptions ssr_options;
  ssr_options.enabled = options.screen_space_reflections;
  ssr_options.thickness = options.ssr_thickness;
  ssr_options.bias = options.ssr_bias;
  ssr_options.maxDistance = options.ssr_max_distance;
  ssr_options.stride = options.ssr_stride;
  impl_->view->setScreenSpaceReflectionsOptions(ssr_options);

  filament::View::MultiSampleAntiAliasingOptions msaa_options;
  msaa_options.enabled = options.msaa;
  msaa_options.sampleCount = options.msaa_sample_count;
  impl_->view->setMultiSampleAntiAliasingOptions(msaa_options);
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::SetEnvironment(
    const StageEnvironment& environment) {
#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->renderer == nullptr) {
    return false;
  }
  filament::Renderer::ClearOptions clear_options;
  clear_options.clearColor = filament::math::float4{
      std::clamp(environment.sky_r, 0.0f, 1.0f),
      std::clamp(environment.sky_g, 0.0f, 1.0f),
      std::clamp(environment.sky_b, 0.0f, 1.0f),
      std::clamp(environment.sky_a, 0.0f, 1.0f),
  };
  clear_options.clear = true;
  impl_->renderer->setClearOptions(clear_options);
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::UpsertLight(const StageLight& light) {
#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->engine == nullptr || impl_->scene == nullptr) {
    return false;
  }
  RemoveLight(light.id);

  utils::Entity entity = utils::EntityManager::get().create();
  const auto type = light.type == STAGE_LIGHT_POINT
                        ? filament::LightManager::Type::POINT
                        : filament::LightManager::Type::DIRECTIONAL;
  auto builder = filament::LightManager::Builder(type)
                     .color({light.color_r, light.color_g, light.color_b})
                     .intensity(std::max(light.intensity, 0.0f))
                     .castShadows(light.cast_shadows != 0);
  if (light.type == STAGE_LIGHT_POINT) {
    builder.position(
        {light.position_x, light.position_y, light.position_z});
    builder.falloff(std::max(light.falloff_radius, 0.001f));
  } else {
    builder.direction(DirectionOrFallback(
        light.direction_x,
        light.direction_y,
        light.direction_z,
        filament::math::float3{0.0f, -1.0f, 0.0f}));
  }
  if (builder.build(*impl_->engine, entity) !=
      filament::LightManager::Builder::Success) {
    utils::EntityManager::get().destroy(entity);
    return false;
  }
  impl_->scene->addEntity(entity);
  impl_->light_entities[light.id] = entity;
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::SetLightPosition(
    int32_t light_id,
    float x,
    float y,
    float z) {
#if defined(STAGE_HAS_FILAMENT)
  if (impl_->engine == nullptr) {
    return false;
  }
  const auto found = impl_->light_entities.find(light_id);
  if (found == impl_->light_entities.end()) {
    return false;
  }
  auto& manager = impl_->engine->getLightManager();
  const auto instance = manager.getInstance(found->second);
  if (!instance.isValid()) {
    return false;
  }
  manager.setPosition(instance, {x, y, z});
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::SetLightDirection(
    int32_t light_id,
    float x,
    float y,
    float z) {
#if defined(STAGE_HAS_FILAMENT)
  if (impl_->engine == nullptr) {
    return false;
  }
  const auto found = impl_->light_entities.find(light_id);
  if (found == impl_->light_entities.end()) {
    return false;
  }
  auto& manager = impl_->engine->getLightManager();
  const auto instance = manager.getInstance(found->second);
  if (!instance.isValid()) {
    return false;
  }
  manager.setDirection(
      instance,
      DirectionOrFallback(x, y, z, filament::math::float3{0.0f, -1.0f, 0.0f}));
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::SetLightIntensity(
    int32_t light_id,
    float intensity) {
#if defined(STAGE_HAS_FILAMENT)
  if (impl_->engine == nullptr) {
    return false;
  }
  const auto found = impl_->light_entities.find(light_id);
  if (found == impl_->light_entities.end()) {
    return false;
  }
  auto& manager = impl_->engine->getLightManager();
  const auto instance = manager.getInstance(found->second);
  if (!instance.isValid()) {
    return false;
  }
  manager.setIntensity(instance, std::max(intensity, 0.0f));
  return true;
#else
  return false;
#endif
}

void StageFilamentRenderer::RemoveLight(int32_t light_id) {
#if defined(STAGE_HAS_FILAMENT)
  const auto found = impl_->light_entities.find(light_id);
  if (found == impl_->light_entities.end()) {
    return;
  }
  if (impl_->scene != nullptr) {
    impl_->scene->remove(found->second);
  }
  if (impl_->engine != nullptr) {
    impl_->engine->getLightManager().destroy(found->second);
  }
  utils::EntityManager::get().destroy(found->second);
  impl_->light_entities.erase(found);
#endif
}

bool StageFilamentRenderer::CreateTexturedMesh(
    int32_t mesh_id,
    const std::vector<MeshVertex>& vertices,
    const std::vector<uint32_t>& indices,
    const MeshMaterial& material) {
#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->engine == nullptr || impl_->scene == nullptr ||
      vertices.empty() || indices.empty()) {
    return false;
  }
  DestroyTexturedMesh(mesh_id);

  filament::MaterialInstance* material_instance = nullptr;
  if (!material.cache_key.empty() && !material.filamat_bytes.empty()) {
    filament::Material* filament_material = nullptr;
    const auto found_material = impl_->material_cache.find(material.cache_key);
    if (found_material != impl_->material_cache.end()) {
      filament_material = found_material->second.material;
    } else {
      filament_material =
          filament::Material::Builder()
              .package(
                  material.filamat_bytes.data(),
                  material.filamat_bytes.size())
              .build(*impl_->engine);
      if (filament_material != nullptr) {
        impl_->material_cache[material.cache_key] = Impl::MaterialResource{
            filament_material,
        };
      }
    }

    if (filament_material != nullptr) {
      material_instance = filament_material->createInstance();
      if (material_instance != nullptr) {
        material_instance->setParameter(
            "tint",
            filament::RgbaType::LINEAR,
            filament::math::float4{
                material.base_color[0],
                material.base_color[1],
                material.base_color[2],
                material.base_color[3],
            });
        material_instance->setParameter("roughness", material.roughness);
        material_instance->setParameter("metallic", material.metallic);
        for (const auto& uniform : material.uniforms) {
          if (uniform.name.empty()) {
            continue;
          }
          switch (uniform.type) {
            case MeshUniform::Type::kFloat:
              material_instance->setParameter(
                  uniform.name.c_str(), uniform.float_value);
              break;
            case MeshUniform::Type::kBool:
              material_instance->setParameter(
                  uniform.name.c_str(), uniform.bool_value);
              break;
            case MeshUniform::Type::kColor:
              material_instance->setParameter(
                  uniform.name.c_str(),
                  filament::RgbaType::LINEAR,
                  filament::math::float4{
                      uniform.color_value[0],
                      uniform.color_value[1],
                      uniform.color_value[2],
                      uniform.color_value[3],
                  });
              break;
          }
        }

        for (const auto& mesh_texture : material.textures) {
          if (mesh_texture.uniform_name.empty() ||
              mesh_texture.cache_key.empty() || mesh_texture.bytes.empty()) {
            continue;
          }
          filament::Texture* texture = nullptr;
          const auto found_texture =
              impl_->texture_cache.find(mesh_texture.cache_key);
          if (found_texture != impl_->texture_cache.end()) {
            texture = found_texture->second.texture;
          } else {
            DecodedImage image;
            if (DecodeImageWithWic(
                    mesh_texture.bytes.data(),
                    mesh_texture.bytes.size(),
                    &image)) {
              if (mesh_texture.has_region) {
                CropImageToRegion(&image, mesh_texture.region);
              }
              texture =
                  filament::Texture::Builder()
                      .width(image.width)
                      .height(image.height)
                      .levels(1)
                      .sampler(filament::Texture::Sampler::SAMPLER_2D)
                      .format(filament::Texture::InternalFormat::SRGB8_A8)
                      .build(*impl_->engine);
              if (texture != nullptr) {
                const size_t byte_count = image.rgba.size();
                auto* texture_bytes = new uint8_t[byte_count];
                std::memcpy(texture_bytes, image.rgba.data(), byte_count);
                texture->setImage(
                    *impl_->engine,
                    0,
                    filament::Texture::PixelBufferDescriptor(
                        texture_bytes,
                        byte_count,
                        filament::Texture::Format::RGBA,
                        filament::Texture::Type::UBYTE,
                        DeleteBuffer));
                impl_->texture_cache[mesh_texture.cache_key] =
                    Impl::TextureResource{texture};
              }
            }
          }
          if (texture != nullptr) {
            filament::TextureSampler sampler(
                filament::TextureSampler::MinFilter::LINEAR,
                filament::TextureSampler::MagFilter::LINEAR,
                filament::TextureSampler::WrapMode::REPEAT);
            material_instance->setParameter(
                mesh_texture.uniform_name.c_str(), texture, sampler);
          }
        }
      }
    }
  }

  filament::VertexBuffer* vertex_buffer =
      filament::VertexBuffer::Builder()
          .vertexCount(static_cast<uint32_t>(vertices.size()))
          .bufferCount(1)
          .attribute(
              filament::VertexAttribute::POSITION,
              0,
              filament::VertexBuffer::AttributeType::FLOAT3,
              offsetof(MeshVertex, position),
              sizeof(MeshVertex))
          .attribute(
              filament::VertexAttribute::UV0,
              0,
              filament::VertexBuffer::AttributeType::FLOAT2,
              offsetof(MeshVertex, uv),
              sizeof(MeshVertex))
          .attribute(
              filament::VertexAttribute::TANGENTS,
              0,
              filament::VertexBuffer::AttributeType::FLOAT4,
              offsetof(MeshVertex, tangent),
              sizeof(MeshVertex))
          .build(*impl_->engine);
  filament::IndexBuffer* index_buffer =
      filament::IndexBuffer::Builder()
          .indexCount(static_cast<uint32_t>(indices.size()))
          .bufferType(filament::IndexBuffer::IndexType::UINT)
          .build(*impl_->engine);
  if (vertex_buffer == nullptr || index_buffer == nullptr) {
    if (material_instance != nullptr) {
      impl_->engine->destroy(material_instance);
    }
    if (vertex_buffer != nullptr) {
      impl_->engine->destroy(vertex_buffer);
    }
    if (index_buffer != nullptr) {
      impl_->engine->destroy(index_buffer);
    }
    return false;
  }

  const size_t vertex_byte_count = vertices.size() * sizeof(MeshVertex);
  auto* vertex_bytes = new uint8_t[vertex_byte_count];
  std::memcpy(vertex_bytes, vertices.data(), vertex_byte_count);
  vertex_buffer->setBufferAt(
      *impl_->engine,
      0,
      filament::VertexBuffer::BufferDescriptor(
          vertex_bytes, vertex_byte_count, DeleteBuffer));

  const size_t index_byte_count = indices.size() * sizeof(uint32_t);
  auto* index_bytes = new uint8_t[index_byte_count];
  std::memcpy(index_bytes, indices.data(), index_byte_count);
  index_buffer->setBuffer(
      *impl_->engine,
      filament::IndexBuffer::BufferDescriptor(
          index_bytes, index_byte_count, DeleteBuffer));

  filament::math::float3 min_bounds{
      vertices.front().position[0],
      vertices.front().position[1],
      vertices.front().position[2],
  };
  filament::math::float3 max_bounds = min_bounds;
  for (const auto& vertex : vertices) {
    min_bounds.x = std::min(min_bounds.x, vertex.position[0]);
    min_bounds.y = std::min(min_bounds.y, vertex.position[1]);
    min_bounds.z = std::min(min_bounds.z, vertex.position[2]);
    max_bounds.x = std::max(max_bounds.x, vertex.position[0]);
    max_bounds.y = std::max(max_bounds.y, vertex.position[1]);
    max_bounds.z = std::max(max_bounds.z, vertex.position[2]);
  }
  const filament::Box bounds{
      (min_bounds + max_bounds) * 0.5f,
      (max_bounds - min_bounds) * 0.5f,
  };

  utils::Entity entity = utils::EntityManager::get().create();
  filament::RenderableManager::Builder builder(1);
  builder
      .boundingBox(bounds)
      .geometry(
          0,
          filament::RenderableManager::PrimitiveType::TRIANGLES,
          vertex_buffer,
          index_buffer,
          0,
          indices.size())
      .castShadows(false)
      .receiveShadows(true);
  if (material_instance != nullptr) {
    builder.material(0, material_instance);
  }
  if (builder.build(*impl_->engine, entity) !=
      filament::RenderableManager::Builder::Success) {
    if (material_instance != nullptr) {
      impl_->engine->destroy(material_instance);
    }
    impl_->engine->destroy(vertex_buffer);
    impl_->engine->destroy(index_buffer);
    utils::EntityManager::get().destroy(entity);
    return false;
  }

  impl_->scene->addEntity(entity);
  impl_->textured_meshes[mesh_id] = Impl::TexturedMesh{
      entity,
      vertex_buffer,
      index_buffer,
      material_instance,
  };
  return true;
#else
  return false;
#endif
}

void StageFilamentRenderer::DestroyTexturedMesh(int32_t mesh_id) {
#if defined(STAGE_HAS_FILAMENT)
  const auto found = impl_->textured_meshes.find(mesh_id);
  if (found == impl_->textured_meshes.end()) {
    return;
  }
  if (impl_->scene != nullptr) {
    impl_->scene->remove(found->second.entity);
  }
  if (impl_->engine != nullptr) {
    impl_->engine->destroy(found->second.entity);
    if (found->second.vertex_buffer != nullptr) {
      impl_->engine->destroy(found->second.vertex_buffer);
    }
    if (found->second.index_buffer != nullptr) {
      impl_->engine->destroy(found->second.index_buffer);
    }
    if (found->second.material_instance != nullptr) {
      impl_->engine->destroy(found->second.material_instance);
    }
  }
  utils::EntityManager::get().destroy(found->second.entity);
  impl_->textured_meshes.erase(found);
#endif
}

void StageFilamentRenderer::RenderFrame() {
#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->renderer == nullptr ||
      impl_->swap_chain == nullptr || impl_->view == nullptr) {
    return;
  }
  if (impl_->renderer->beginFrame(impl_->swap_chain)) {
    impl_->renderer->render(impl_->view);
    impl_->renderer->endFrame();
  }
#endif
}

bool StageFilamentRenderer::LoadModelAssetFromMemory(
    int32_t asset_id,
    const uint8_t* bytes,
    uint32_t byte_count,
    ModelBounds* out_bounds) {
  impl_->last_error.clear();
#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->asset_loader == nullptr ||
      impl_->resource_loader == nullptr) {
    impl_->last_error = "Filament renderer is not initialized.";
    return false;
  }
  if (bytes == nullptr || byte_count == 0) {
    impl_->last_error = "Model asset byte buffer is empty.";
    return false;
  }
  if (impl_->model_assets.find(asset_id) != impl_->model_assets.end()) {
    impl_->last_error = "Model asset id is already loaded.";
    return false;
  }

  filament::gltfio::FilamentAsset* asset =
      impl_->asset_loader->createAsset(bytes, byte_count);
  if (asset == nullptr) {
    std::ostringstream message;
    message << "AssetLoader::createAsset returned null for " << byte_count
            << " bytes.";
    if (byte_count >= 4) {
      message << " Magic="
              << static_cast<char>(bytes[0])
              << static_cast<char>(bytes[1])
              << static_cast<char>(bytes[2])
              << static_cast<char>(bytes[3])
              << ".";
    }
    impl_->last_error = message.str();
    return false;
  }

  if (!impl_->resource_loader->loadResources(asset)) {
    std::ostringstream message;
    message << "ResourceLoader::loadResources failed. External resource URI "
            << "count=" << asset->getResourceUriCount() << ".";
    const char* const* uris = asset->getResourceUris();
    for (size_t index = 0; index < asset->getResourceUriCount(); ++index) {
      message << " [" << index
              << "]=" << (uris[index] == nullptr ? "" : uris[index]);
    }
    impl_->last_error = message.str();
    impl_->asset_loader->destroyAsset(asset);
    return false;
  }
  impl_->resource_loader->evictResourceData();

  const auto bounds = asset->getBoundingBox();
  const auto center = bounds.center();
  const auto half_extent = bounds.extent();
  if (out_bounds != nullptr) {
    out_bounds->center[0] = center[0];
    out_bounds->center[1] = center[1];
    out_bounds->center[2] = center[2];
    out_bounds->half_extent[0] = half_extent[0];
    out_bounds->half_extent[1] = half_extent[1];
    out_bounds->half_extent[2] = half_extent[2];
  }

  impl_->model_assets.emplace(
      asset_id,
      Impl::ModelAsset{
          asset,
      });
  return true;
#else
  impl_->last_error =
      "Stage 3D was built without STAGE_HAS_FILAMENT for Windows.";
  return false;
#endif
}

const std::string& StageFilamentRenderer::LastError() const {
  return impl_->last_error;
}

bool StageFilamentRenderer::UnloadModelAsset(int32_t asset_id) {
#if defined(STAGE_HAS_FILAMENT)
  if (impl_->asset_loader == nullptr) {
    return false;
  }
  for (const auto& instance : impl_->model_instances) {
    if (instance.second.asset_id == asset_id) {
      return false;
    }
  }
  const auto found = impl_->model_assets.find(asset_id);
  if (found == impl_->model_assets.end()) {
    return false;
  }
  impl_->pooled_model_instances.erase(asset_id);
  impl_->asset_loader->destroyAsset(found->second.asset);
  impl_->model_assets.erase(found);
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::CreateModelInstance(
    int32_t instance_id,
    int32_t asset_id,
    bool cast_shadows,
    bool receive_shadows) {
#if defined(STAGE_HAS_FILAMENT)
  if (!impl_->initialized || impl_->asset_loader == nullptr ||
      impl_->scene == nullptr) {
    return false;
  }
  DestroyModelInstance(instance_id);
  const auto found_asset = impl_->model_assets.find(asset_id);
  if (found_asset == impl_->model_assets.end()) {
    return false;
  }
  filament::gltfio::FilamentInstance* instance = nullptr;
  auto& pooled_instances = impl_->pooled_model_instances[asset_id];
  if (!pooled_instances.empty()) {
    instance = pooled_instances.back();
    pooled_instances.pop_back();
  } else {
    instance = impl_->asset_loader->createInstance(found_asset->second.asset);
  }
  if (instance == nullptr) {
    return false;
  }
  impl_->scene->addEntities(instance->getEntities(), instance->getEntityCount());
  auto& renderable_manager = impl_->engine->getRenderableManager();
  const utils::Entity* entities = instance->getEntities();
  const size_t entity_count = instance->getEntityCount();
  for (size_t i = 0; i < entity_count; ++i) {
    const auto renderable = renderable_manager.getInstance(entities[i]);
    if (!renderable.isValid()) {
      continue;
    }
    renderable_manager.setCastShadows(renderable, cast_shadows);
    renderable_manager.setReceiveShadows(renderable, receive_shadows);
  }
  impl_->model_instances[instance_id] = Impl::ModelInstance{
      asset_id,
      instance,
  };
  return true;
#else
  return false;
#endif
}

void StageFilamentRenderer::DestroyModelInstance(int32_t instance_id) {
#if defined(STAGE_HAS_FILAMENT)
  const auto found = impl_->model_instances.find(instance_id);
  if (found == impl_->model_instances.end()) {
    return;
  }
  if (impl_->scene != nullptr && found->second.instance != nullptr) {
    impl_->scene->removeEntities(
        found->second.instance->getEntities(),
        found->second.instance->getEntityCount());
  }
  if (found->second.instance != nullptr) {
    impl_->pooled_model_instances[found->second.asset_id].push_back(
        found->second.instance);
  }
  impl_->model_instances.erase(found);
#endif
}

bool StageFilamentRenderer::SetModelTransform(
    int32_t instance_id,
    const float* matrix_16) {
#if defined(STAGE_HAS_FILAMENT)
  if (impl_->engine == nullptr || matrix_16 == nullptr) {
    return false;
  }
  const auto found = impl_->model_instances.find(instance_id);
  if (found == impl_->model_instances.end() ||
      found->second.instance == nullptr) {
    return false;
  }
  auto& manager = impl_->engine->getTransformManager();
  const auto transform_instance =
      manager.getInstance(found->second.instance->getRoot());
  if (!transform_instance.isValid()) {
    return false;
  }
  const filament::math::mat4f transform{
      filament::math::float4{matrix_16[0], matrix_16[1], matrix_16[2], matrix_16[3]},
      filament::math::float4{matrix_16[4], matrix_16[5], matrix_16[6], matrix_16[7]},
      filament::math::float4{matrix_16[8], matrix_16[9], matrix_16[10], matrix_16[11]},
      filament::math::float4{matrix_16[12], matrix_16[13], matrix_16[14], matrix_16[15]},
  };
  manager.setTransform(transform_instance, transform);
  return true;
#else
  return false;
#endif
}

std::vector<StageFilamentRenderer::ModelAnimation>
StageFilamentRenderer::GetModelAnimations(int32_t instance_id) const {
  std::vector<ModelAnimation> animations;
#if defined(STAGE_HAS_FILAMENT)
  const auto found = impl_->model_instances.find(instance_id);
  if (found == impl_->model_instances.end() ||
      found->second.instance == nullptr) {
    return animations;
  }
  const auto* animator = found->second.instance->getAnimator();
  if (animator == nullptr) {
    return animations;
  }
  const size_t count = animator->getAnimationCount();
  animations.reserve(count);
  for (size_t index = 0; index < count; ++index) {
    const char* name = animator->getAnimationName(index);
    animations.push_back(ModelAnimation{
        static_cast<int32_t>(index),
        name == nullptr ? std::string() : std::string(name),
        animator->getAnimationDuration(index),
    });
  }
#endif
  return animations;
}

bool StageFilamentRenderer::GetModelAnimationDuration(
    int32_t instance_id,
    int32_t animation_index,
    float* out_duration_seconds) const {
#if defined(STAGE_HAS_FILAMENT)
  if (out_duration_seconds == nullptr || animation_index < 0) {
    return false;
  }
  const auto found = impl_->model_instances.find(instance_id);
  if (found == impl_->model_instances.end() ||
      found->second.instance == nullptr) {
    return false;
  }
  const auto* animator = found->second.instance->getAnimator();
  if (animator == nullptr ||
      static_cast<size_t>(animation_index) >= animator->getAnimationCount()) {
    return false;
  }
  *out_duration_seconds =
      animator->getAnimationDuration(static_cast<size_t>(animation_index));
  return true;
#else
  return false;
#endif
}

bool StageFilamentRenderer::ApplyModelAnimationFrame(
    int32_t instance_id,
    int32_t animation_index,
    float animation_time_seconds) {
#if defined(STAGE_HAS_FILAMENT)
  if (animation_index < 0) {
    return false;
  }
  const auto found = impl_->model_instances.find(instance_id);
  if (found == impl_->model_instances.end() ||
      found->second.instance == nullptr) {
    return false;
  }
  auto* animator = found->second.instance->getAnimator();
  if (animator == nullptr ||
      static_cast<size_t>(animation_index) >= animator->getAnimationCount()) {
    return false;
  }
  animator->applyAnimation(
      static_cast<size_t>(animation_index),
      std::max(animation_time_seconds, 0.0f));
  animator->updateBoneMatrices();
  return true;
#else
  return false;
#endif
}

}  // namespace stage_3d
