import 'package:flutter/services.dart';

import 'render_options.dart';
import 'render_scene_bridge.dart';

/// Manages view-level render quality and post-processing settings.
final class RenderOptionsController {
  RenderOptionsController({RenderOptions? initialOptions})
    : _options = initialOptions ?? const RenderOptions();

  RenderSceneBridge? _bridge;
  RenderOptions _options;

  RenderOptions get options => _options;

  void attach(MethodChannel channel) {
    attachBridge(MethodChannelRenderSceneBridge(channel));
  }

  void attachBridge(RenderSceneBridge bridge) {
    _bridge = bridge;
    _bridge?.setRenderOptions(_options);
  }

  void detach() {
    _bridge = null;
  }

  void setOptions(RenderOptions options) {
    _options = options;
    _bridge?.setRenderOptions(options);
  }
}
