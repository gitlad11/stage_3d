package com.stage3d.stage_3d

import io.flutter.embedding.engine.plugins.FlutterPlugin

class Stage3DPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding
            .platformViewRegistry
            .registerViewFactory(
                FilamentPlatformViewFactory.viewType,
                FilamentPlatformViewFactory(binding.binaryMessenger),
            )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
