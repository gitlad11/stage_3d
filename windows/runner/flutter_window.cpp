#include "flutter_window.h"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <optional>
#include <string>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"
#include "stage_filament_renderer.h"
#include "stage_windows_renderer_bridge.h"

namespace {

constexpr UINT_PTR kFilamentFrameTimer = 1;
constexpr UINT kFilamentFrameMs = 16;
constexpr wchar_t kFilamentPreviewWindowClass[] =
    L"STAGE_3D_FILAMENT_PREVIEW_WINDOW";

bool IsFilamentPreviewEnabled() {
  wchar_t* value = nullptr;
  size_t value_size = 0;
  if (_wdupenv_s(&value, &value_size, L"STAGE_FILAMENT_PREVIEW") != 0 ||
      value == nullptr) {
    return true;
  }
  std::wstring flag(value);
  free(value);
  return !(flag == L"0" || flag == L"false" || flag == L"FALSE" ||
           flag == L"off" || flag == L"OFF" || flag == L"no" ||
           flag == L"NO");
}

std::filesystem::path ExecutableDirectory() {
  std::wstring buffer(MAX_PATH, L'\0');
  const DWORD size = GetModuleFileNameW(
      nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  buffer.resize(size);
  return std::filesystem::path(buffer).parent_path();
}

void LogFilamentPreview(const std::string& message) {
  std::ofstream log(
      ExecutableDirectory() / L"stage_windows_preview.log",
      std::ios::app);
  log << message << "\n";
}

ATOM RegisterFilamentPreviewWindowClass() {
  WNDCLASS window_class{};
  window_class.style = CS_DBLCLKS;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kFilamentPreviewWindowClass;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpfnWndProc = FlutterWindow::FilamentPreviewWindowProc;
  window_class.hbrBackground =
      reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  return RegisterClass(&window_class);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  filament_preview_enabled_ = IsFilamentPreviewEnabled();
  LogFilamentPreview(
      filament_preview_enabled_
          ? "STAGE_FILAMENT_PREVIEW enabled."
          : "STAGE_FILAMENT_PREVIEW disabled.");
  if (filament_preview_enabled_) {
    CreateFilamentPreviewWindow();
  }
  renderer_bridge_ = std::make_unique<StageWindowsRendererBridge>(
      flutter_controller_->engine()->messenger(),
      L"data\\flutter_assets",
      filament_renderer_.get());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kFilamentFrameTimer);
  renderer_bridge_.reset();
  DestroyFilamentPreviewWindow();
  filament_renderer_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_SIZE:
      LayoutFilamentPreviewWindow();
      break;

    case WM_TIMER:
      if (wparam == kFilamentFrameTimer && filament_renderer_) {
        if (renderer_bridge_) {
          renderer_bridge_->TickAnimations();
        }
        filament_renderer_->RenderFrame();
        return 0;
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::CreateFilamentPreviewWindow() {
  RegisterFilamentPreviewWindowClass();

  filament_window_ = CreateWindowEx(
      0, kFilamentPreviewWindowClass, L"Stage 3D Filament Preview",
      WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0, 0, 1, 1, GetHandle(),
      nullptr, GetModuleHandle(nullptr), this);
  if (filament_window_ == nullptr) {
    LogFilamentPreview("CreateWindowEx failed for Filament preview.");
    return;
  }
  LogFilamentPreview("Filament preview child window created.");

  LayoutFilamentPreviewWindow();
  RECT viewport{};
  GetClientRect(filament_window_, &viewport);

  filament_renderer_ = std::make_unique<stage_3d::StageFilamentRenderer>();
  if (!filament_renderer_->Initialize(
          filament_window_, viewport.right - viewport.left,
          viewport.bottom - viewport.top)) {
    LogFilamentPreview("StageFilamentRenderer::Initialize failed.");
    filament_renderer_.reset();
    DestroyFilamentPreviewWindow();
    return;
  }
  LogFilamentPreview("StageFilamentRenderer::Initialize succeeded.");

  SetTimer(GetHandle(), kFilamentFrameTimer, kFilamentFrameMs, nullptr);
  if (renderer_bridge_) {
    renderer_bridge_->TickAnimations();
  }
  filament_renderer_->RenderFrame();
}

LRESULT CALLBACK FlutterWindow::FilamentPreviewWindowProc(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(
        hwnd,
        GWLP_USERDATA,
        reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
    return TRUE;
  }

  auto* window = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (window != nullptr) {
    return window->HandleFilamentPreviewMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT FlutterWindow::HandleFilamentPreviewMessage(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  switch (message) {
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
      filament_dragging_ = true;
      filament_last_cursor_ = POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      SetCapture(hwnd);
      return 0;

    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
      filament_dragging_ = false;
      if (GetCapture() == hwnd) {
        ReleaseCapture();
      }
      return 0;

    case WM_MOUSEMOVE:
      if (filament_dragging_ && renderer_bridge_ && filament_renderer_) {
        const POINT cursor{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        const float delta_x =
            static_cast<float>(cursor.x - filament_last_cursor_.x);
        const float delta_y =
            static_cast<float>(cursor.y - filament_last_cursor_.y);
        filament_last_cursor_ = cursor;
        if ((wparam & MK_RBUTTON) != 0 ||
            (GetKeyState(VK_SHIFT) & 0x8000) != 0) {
          renderer_bridge_->MoveCamera(delta_x, delta_y);
        } else {
          renderer_bridge_->OrbitCamera(delta_x * 0.01f, -delta_y * 0.01f);
        }
        filament_renderer_->RenderFrame();
      }
      return 0;

    case WM_MOUSEWHEEL:
      if (renderer_bridge_ && filament_renderer_) {
        renderer_bridge_->ZoomCamera(
            static_cast<float>(GET_WHEEL_DELTA_WPARAM(wparam)));
        filament_renderer_->RenderFrame();
      }
      return 0;

    case WM_LBUTTONDBLCLK:
      if (renderer_bridge_ && filament_renderer_) {
        renderer_bridge_->ResetCamera();
        filament_renderer_->RenderFrame();
      }
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::DestroyFilamentPreviewWindow() {
  if (filament_window_ != nullptr) {
    DestroyWindow(filament_window_);
    filament_window_ = nullptr;
  }
}

void FlutterWindow::LayoutFilamentPreviewWindow() {
  if (filament_window_ == nullptr) {
    return;
  }

  RECT frame = GetClientArea();
  const int frame_width = frame.right - frame.left;
  const int frame_height = frame.bottom - frame.top;
  if (frame_width <= 0 || frame_height <= 0) {
    return;
  }

  SetWindowPos(
      filament_window_,
      HWND_TOP,
      0,
      0,
      frame_width,
      frame_height,
      SWP_SHOWWINDOW);

  if (filament_renderer_) {
    filament_renderer_->Resize(frame_width, frame_height);
    if (renderer_bridge_) {
      renderer_bridge_->TickAnimations();
    }
    filament_renderer_->RenderFrame();
  }
}
