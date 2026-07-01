#ifndef RUNNER_STAGE_WINDOWS_RENDERER_BRIDGE_H_
#define RUNNER_STAGE_WINDOWS_RENDERER_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <unordered_set>
#include <vector>

#include "stage_filament_renderer.h"

struct StageEngine;

class StageWindowsRendererBridge {
 public:
  StageWindowsRendererBridge(
      flutter::BinaryMessenger* messenger,
      std::wstring assets_path,
      stage_3d::StageFilamentRenderer* renderer,
      std::function<void()> request_render,
      std::function<void(bool)> set_animation_loop_active);
  ~StageWindowsRendererBridge();

  StageWindowsRendererBridge(const StageWindowsRendererBridge&) = delete;
  StageWindowsRendererBridge& operator=(const StageWindowsRendererBridge&) =
      delete;

  void TickAnimations();
  bool HasActiveAnimations() const;
  void OrbitCamera(float delta_yaw, float delta_pitch);
  void MoveCamera(float delta_x, float delta_y);
  void ZoomCamera(float wheel_delta);
  void ResetCamera();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ApplyCamera();
  void NotifyAnimationLoopState();
  void RequestRender();

  std::wstring ResolveAssetPath(const std::string& asset_path) const;
  bool ReadAssetBytes(
      const std::string& asset_path,
      std::vector<uint8_t>* out_bytes) const;
  stage_3d::StageFilamentRenderer::MeshMaterial MeshMaterialFromMessage(
      const flutter::EncodableMap& map) const;
  std::optional<stage_3d::StageFilamentRenderer::MeshTexture>
  MeshTextureFromMessage(
      const flutter::EncodableMap& map,
      const std::string& uniform_name) const;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::wstring assets_path_;
  stage_3d::StageFilamentRenderer* renderer_ = nullptr;
  StageEngine* engine_ = nullptr;
  std::unordered_set<int32_t> animated_instances_;
  std::function<void()> request_render_;
  std::function<void(bool)> set_animation_loop_active_;
};

#endif  // RUNNER_STAGE_WINDOWS_RENDERER_BRIDGE_H_
