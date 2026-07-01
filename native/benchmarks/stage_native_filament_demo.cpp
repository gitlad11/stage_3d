#include <windows.h>
#include <windowsx.h>

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "stage_3d/stage_engine.h"
#include "stage_filament_renderer.h"

namespace {

constexpr wchar_t kWindowClassName[] = L"STAGE_NATIVE_FILAMENT_DEMO";
constexpr int32_t kFoxAssetId = 1;
constexpr int32_t kOakAssetId = 2;
constexpr int32_t kFoxInstanceId = 1;
constexpr int32_t kOakInstanceId = 2;

struct ModelPlacement {
  int32_t instance_id = 0;
  float x = 0.0f;
  float y = 0.0f;
  float z = 0.0f;
};

struct DemoApp {
  HWND hwnd = nullptr;
  std::unique_ptr<stage_3d::StageFilamentRenderer> renderer;
  StageEngine* engine = nullptr;
  bool running = true;
  bool animate = true;
  bool shadows = true;
  bool dragging = false;
  POINT last_cursor = {0, 0};
  int32_t fox_animation = -1;
  float fox_animation_duration = 0.0f;
  std::chrono::steady_clock::time_point last_title_update;
  uint32_t frames_since_title = 0;
};

DemoApp* g_app = nullptr;

int64_t NowNanos() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

std::filesystem::path RepoRootFromWorkingDirectory() {
  auto current = std::filesystem::current_path();
  for (int depth = 0; depth < 6; ++depth) {
    if (std::filesystem::exists(current / "assets" / "models" / "Fox.glb") &&
        std::filesystem::exists(current / "native" / "include")) {
      return current;
    }
    if (!current.has_parent_path()) {
      break;
    }
    current = current.parent_path();
  }
  return std::filesystem::current_path();
}

std::vector<uint8_t> ReadBytes(const std::filesystem::path& path) {
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file) {
    return {};
  }
  const auto size = file.tellg();
  if (size <= 0) {
    return {};
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  file.seekg(0);
  file.read(reinterpret_cast<char*>(bytes.data()), size);
  return bytes;
}

void ShowError(const std::wstring& message) {
  MessageBox(nullptr, message.c_str(), L"Stage Native Filament Demo", MB_ICONERROR);
}

void ApplyMatrix(DemoApp* app, int32_t instance_id) {
  float matrix[16];
  if (stage_engine_get_model_matrix(app->engine, instance_id, matrix) != 0) {
    app->renderer->SetModelTransform(instance_id, matrix);
  }
}

bool LoadModel(
    DemoApp* app,
    int32_t asset_id,
    const std::filesystem::path& path,
    float normalized_scale,
    int32_t vertical_anchor) {
  const auto bytes = ReadBytes(path);
  if (bytes.empty()) {
    ShowError(L"Could not read model: " + path.wstring());
    return false;
  }

  stage_3d::StageFilamentRenderer::ModelBounds bounds;
  if (!app->renderer->LoadModelAssetFromMemory(
          asset_id,
          bytes.data(),
          static_cast<uint32_t>(bytes.size()),
          &bounds)) {
    const std::string error = app->renderer->LastError();
    ShowError(L"Filament failed to load model: " + path.wstring() + L"\n" +
              std::wstring(error.begin(), error.end()));
    return false;
  }

  stage_engine_register_model_asset(
      app->engine,
      asset_id,
      normalized_scale,
      vertical_anchor,
      StageModelBounds{
          bounds.center[0],
          bounds.center[1],
          bounds.center[2],
          bounds.half_extent[0],
          bounds.half_extent[1],
          bounds.half_extent[2],
      });
  return true;
}

void ConfigureScene(DemoApp* app) {
  stage_engine_set_orbit_camera(
      app->engine,
      StageOrbitCamera{
          0.0f,
          0.65f,
          0.9f,
          -0.55f,
          0.28f,
          5.2f,
      });
  app->renderer->SetCamera(stage_engine_get_camera(app->engine));
  app->renderer->SetEnvironment(StageEnvironment{
      0.035f,
      0.045f,
      0.055f,
      1.0f,
      52000.0f,
      0.85f,
  });
  app->renderer->SetRenderOptions(stage_3d::StageFilamentRenderer::RenderOptions{
      true,
      true,
      2,
      true,
      0.35f,
      0.55f,
      1.0f,
      0,
      false,
      0.1f,
      384,
      6,
      true,
      0,
      false,
      0.1f,
      0.01f,
      3.0f,
      2.0f,
      true,
      2,
  });
  app->renderer->UpsertLight(StageLight{
      1,
      STAGE_LIGHT_DIRECTIONAL,
      1.0f,
      1.0f,
      1.0f,
      125000.0f,
      0.0f,
      0.0f,
      0.0f,
      -0.35f,
      -0.85f,
      -0.25f,
      10.0f,
      1,
  });
}

bool CreateScene(DemoApp* app, const std::filesystem::path& repo_root) {
  const auto model_dir = repo_root / "assets" / "models";
  if (!LoadModel(
          app,
          kFoxAssetId,
          model_dir / "Fox.glb",
          1.2f,
          STAGE_MODEL_ANCHOR_BOTTOM)) {
    return false;
  }
  if (!LoadModel(
          app,
          kOakAssetId,
          model_dir / "mighty_oak_trees.glb",
          8.8f,
          STAGE_MODEL_ANCHOR_BOTTOM)) {
    return false;
  }

  stage_engine_create_model_instance(app->engine, kFoxInstanceId, kFoxAssetId);
  app->renderer->CreateModelInstance(kFoxInstanceId, kFoxAssetId);
  stage_engine_set_model_transform(
      app->engine,
      kFoxInstanceId,
      StageModelTransform{-1.1f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f});
  ApplyMatrix(app, kFoxInstanceId);

  const std::vector<ModelPlacement> oak_placements = {
      {kOakInstanceId, -1.1f, 0.0f, 1.85f},
      {100, -5.2f, 0.0f, 4.8f},
      {101, -3.7f, 0.0f, 6.2f},
      {102, -1.8f, 0.0f, 5.5f},
      {103, 0.6f, 0.0f, 6.0f},
      {104, 2.8f, 0.0f, 5.2f},
      {105, 5.0f, 0.0f, 3.9f},
      {106, -5.8f, 0.0f, 1.6f},
      {107, 5.7f, 0.0f, 1.3f},
      {108, -4.2f, 0.0f, -1.2f},
      {109, 4.3f, 0.0f, -1.4f},
  };
  for (const auto& placement : oak_placements) {
    stage_engine_create_model_instance(
        app->engine, placement.instance_id, kOakAssetId);
    app->renderer->CreateModelInstance(
        placement.instance_id, kOakAssetId, false, false);
    stage_engine_set_model_transform(
        app->engine,
        placement.instance_id,
        StageModelTransform{
            placement.x,
            placement.y,
            placement.z,
            0.0f,
            0.0f,
            0.0f,
            1.0f});
    ApplyMatrix(app, placement.instance_id);
  }

  const auto animations = app->renderer->GetModelAnimations(kFoxInstanceId);
  if (!animations.empty()) {
    app->fox_animation = animations.front().index;
    app->fox_animation_duration = animations.front().duration_seconds;
    stage_engine_play_model_animation(
        app->engine,
        kFoxInstanceId,
        app->fox_animation,
        1,
        1.0f,
        NowNanos(),
        0);
  }
  return true;
}

void UpdateAnimation(DemoApp* app) {
  if (!app->animate || app->fox_animation < 0 || app->fox_animation_duration <= 0.0f) {
    return;
  }
  int32_t sampled_index = -1;
  float animation_time = 0.0f;
  if (stage_engine_sample_model_animation(
          app->engine,
          kFoxInstanceId,
          NowNanos(),
          app->fox_animation_duration,
          &sampled_index,
          &animation_time) == 0) {
    return;
  }
  app->renderer->ApplyModelAnimationFrame(
      kFoxInstanceId,
      sampled_index,
      animation_time);
}

void UpdateWindowTitle(DemoApp* app) {
  app->frames_since_title += 1;
  const auto now = std::chrono::steady_clock::now();
  if (app->last_title_update.time_since_epoch().count() == 0) {
    app->last_title_update = now;
    return;
  }
  const double seconds =
      std::chrono::duration<double>(now - app->last_title_update).count();
  if (seconds < 1.0) {
    return;
  }
  const double fps = app->frames_since_title / seconds;
  std::wstringstream title;
  title << L"Stage Native Filament Demo  FPS " << static_cast<int>(fps + 0.5)
        << L"  animation " << (app->animate ? L"on" : L"off")
        << L"  shadows " << (app->shadows ? L"on" : L"off")
        << L"  [Space animation, S shadows, Esc quit]";
  SetWindowText(app->hwnd, title.str().c_str());
  app->last_title_update = now;
  app->frames_since_title = 0;
}

void ToggleAnimation(DemoApp* app) {
  app->animate = !app->animate;
  if (app->animate && app->fox_animation >= 0) {
    stage_engine_resume_model_animation(app->engine, kFoxInstanceId, NowNanos());
  } else {
    stage_engine_pause_model_animation(app->engine, kFoxInstanceId, NowNanos());
  }
}

void ToggleShadows(DemoApp* app) {
  app->shadows = !app->shadows;
  auto options = stage_3d::StageFilamentRenderer::RenderOptions{};
  options.shadows = app->shadows;
  options.shadow_type = 2;
  options.ambient_occlusion = true;
  options.ambient_occlusion_radius = 0.35f;
  options.ambient_occlusion_intensity = 0.55f;
  options.ambient_occlusion_quality = 0;
  options.msaa = true;
  options.msaa_sample_count = 2;
  app->renderer->SetRenderOptions(options);
}

void ApplyCamera(DemoApp* app) {
  if (app == nullptr || app->renderer == nullptr || app->engine == nullptr) {
    return;
  }
  app->renderer->SetCamera(stage_engine_get_camera(app->engine));
}

void OrbitCamera(DemoApp* app, float delta_yaw, float delta_pitch) {
  stage_engine_orbit_camera(app->engine, delta_yaw, delta_pitch);
  ApplyCamera(app);
}

void MoveCamera(DemoApp* app, float delta_x, float delta_y) {
  stage_engine_move_camera(app->engine, delta_x, delta_y);
  ApplyCamera(app);
}

void ZoomCamera(DemoApp* app, float wheel_delta) {
  StageOrbitCamera camera = stage_engine_get_orbit_camera(app->engine);
  camera.distance *= wheel_delta > 0.0f ? 0.9f : 1.1f;
  stage_engine_set_orbit_camera(app->engine, camera);
  ApplyCamera(app);
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_SIZE:
      if (g_app != nullptr && g_app->renderer) {
        const int width = LOWORD(lparam);
        const int height = HIWORD(lparam);
        if (width > 0 && height > 0) {
          g_app->renderer->Resize(width, height);
        }
      }
      return 0;
    case WM_KEYDOWN:
      if (g_app != nullptr) {
        if (wparam == VK_ESCAPE) {
          PostQuitMessage(0);
          return 0;
        }
        if (wparam == VK_SPACE) {
          ToggleAnimation(g_app);
          return 0;
        }
        if (wparam == 'S') {
          ToggleShadows(g_app);
          return 0;
        }
        if (wparam == VK_LEFT) {
          MoveCamera(g_app, -16.0f, 0.0f);
          return 0;
        }
        if (wparam == VK_RIGHT) {
          MoveCamera(g_app, 16.0f, 0.0f);
          return 0;
        }
        if (wparam == VK_UP) {
          MoveCamera(g_app, 0.0f, -16.0f);
          return 0;
        }
        if (wparam == VK_DOWN) {
          MoveCamera(g_app, 0.0f, 16.0f);
          return 0;
        }
      }
      break;
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
      if (g_app != nullptr) {
        g_app->dragging = true;
        g_app->last_cursor = POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        SetCapture(hwnd);
      }
      return 0;
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
      if (g_app != nullptr) {
        g_app->dragging = false;
      }
      if (GetCapture() == hwnd) {
        ReleaseCapture();
      }
      return 0;
    case WM_MOUSEMOVE:
      if (g_app != nullptr && g_app->dragging) {
        const POINT cursor{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        const float delta_x =
            static_cast<float>(cursor.x - g_app->last_cursor.x);
        const float delta_y =
            static_cast<float>(cursor.y - g_app->last_cursor.y);
        g_app->last_cursor = cursor;
        if ((wparam & MK_RBUTTON) != 0 ||
            (GetKeyState(VK_SHIFT) & 0x8000) != 0) {
          MoveCamera(g_app, delta_x, delta_y);
        } else {
          OrbitCamera(g_app, delta_x * 0.01f, -delta_y * 0.01f);
        }
      }
      return 0;
    case WM_MOUSEWHEEL:
      if (g_app != nullptr) {
        ZoomCamera(g_app, static_cast<float>(GET_WHEEL_DELTA_WPARAM(wparam)));
      }
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

HWND CreateDemoWindow(HINSTANCE instance) {
  WNDCLASS window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClass(&window_class);

  return CreateWindowEx(
      0,
      kWindowClassName,
      L"Stage Native Filament Demo",
      WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      1280,
      720,
      nullptr,
      nullptr,
      instance,
      nullptr);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  DemoApp app;
  g_app = &app;
  app.engine = stage_engine_create();
  app.renderer = std::make_unique<stage_3d::StageFilamentRenderer>();
  app.hwnd = CreateDemoWindow(instance);
  if (app.hwnd == nullptr) {
    ShowError(L"Could not create Win32 window.");
    return 1;
  }

  RECT client{};
  GetClientRect(app.hwnd, &client);
  if (!app.renderer->Initialize(
          app.hwnd,
          client.right - client.left,
          client.bottom - client.top)) {
    ShowError(L"StageFilamentRenderer::Initialize failed.");
    return 1;
  }

  ConfigureScene(&app);
  if (!CreateScene(&app, RepoRootFromWorkingDirectory())) {
    return 1;
  }

  MSG message{};
  while (app.running) {
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        app.running = false;
        break;
      }
      TranslateMessage(&message);
      DispatchMessage(&message);
    }
    if (!app.running) {
      break;
    }
    UpdateAnimation(&app);
    app.renderer->RenderFrame();
    UpdateWindowTitle(&app);
    std::this_thread::sleep_for(std::chrono::milliseconds(33));
  }

  app.renderer.reset();
  stage_engine_destroy(app.engine);
  g_app = nullptr;
  return 0;
}
