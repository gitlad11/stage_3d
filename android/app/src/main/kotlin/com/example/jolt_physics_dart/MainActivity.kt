package com.example.jolt_physics_dart

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                FilamentPlatformViewFactory.viewType,
                FilamentPlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}

