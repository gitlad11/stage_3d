#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

namespace stage_3d {
class StageFilamentRenderer;
}
class StageWindowsRendererBridge;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  static LRESULT CALLBACK FilamentPreviewWindowProc(
      HWND hwnd,
      UINT message,
      WPARAM wparam,
      LPARAM lparam);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void CreateFilamentPreviewWindow();
  void DestroyFilamentPreviewWindow();
  void LayoutFilamentPreviewWindow();
  void RenderFilamentFrame(bool tick_animations = false);
  void SetFilamentAnimationLoopActive(bool active);
  LRESULT HandleFilamentPreviewMessage(
      HWND hwnd,
      UINT message,
      WPARAM wparam,
      LPARAM lparam);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native Filament preview lifecycle. This is intentionally a separate child
  // HWND so the SwapChain never attaches to Flutter's own child window.
  std::unique_ptr<stage_3d::StageFilamentRenderer> filament_renderer_;
  std::unique_ptr<StageWindowsRendererBridge> renderer_bridge_;
  HWND filament_window_ = nullptr;
  bool filament_preview_enabled_ = false;
  bool filament_frame_timer_active_ = false;
  bool filament_dragging_ = false;
  POINT filament_last_cursor_ = {0, 0};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
