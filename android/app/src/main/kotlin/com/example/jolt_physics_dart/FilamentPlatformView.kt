package com.example.jolt_physics_dart

import android.content.Context
import android.view.Choreographer
import android.view.TextureView
import com.google.android.filament.EntityManager
import com.google.android.filament.LightManager
import com.google.android.filament.Skybox
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.FilamentInstance
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.utils.ModelViewer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer

class FilamentPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
) : PlatformView, MethodChannel.MethodCallHandler, Choreographer.FrameCallback {
    private val textureView = TextureView(context)
    private val modelViewer = ModelViewer(textureView)
    private val channel = MethodChannel(messenger, "filament_view_$viewId")
    private val choreographer = Choreographer.getInstance()
    private val startNanos = System.nanoTime()
    private val materialProvider = UbershaderProvider(modelViewer.engine)
    private val assetLoader = AssetLoader(modelViewer.engine, materialProvider, EntityManager.get())
    private val resourceLoader = ResourceLoader(modelViewer.engine)
    private var disposed = false
    private val lights = mutableMapOf<Int, Int>()
    private val assets = mutableMapOf<Int, NativeModelAsset>()
    private val instances = mutableMapOf<Int, NativeModelInstance>()

    init {
        textureView.setOnTouchListener(modelViewer)
        channel.setMethodCallHandler(this)
        modelViewer.scene.skybox =
            Skybox.Builder().color(0.025f, 0.06f, 0.11f, 1.0f).build(modelViewer.engine)
        modelViewer.scene.removeEntity(modelViewer.light)
        choreographer.postFrameCallback(this)
    }

    override fun getView() = textureView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resetView" -> {
                modelViewer.resetToDefaultState()
                result.success(null)
            }
            "loadModelAsset" -> {
                loadModelAsset(context, call)
                result.success(null)
            }
            "createModelInstance" -> {
                createModelInstance(call)
                result.success(null)
            }
            "setModelTransform" -> {
                updateModelTransform(call)
                result.success(null)
            }
            "destroyModelInstance" -> {
                destroyModelInstance(call.int("instanceId"))
                result.success(null)
            }
            "getModelAnimations" -> {
                result.success(getModelAnimations(call.int("instanceId")))
            }
            "playModelAnimation" -> {
                playModelAnimation(call)
                result.success(null)
            }
            "pauseModelAnimation" -> {
                pauseModelAnimation(call.int("instanceId"))
                result.success(null)
            }
            "resumeModelAnimation" -> {
                resumeModelAnimation(call.int("instanceId"))
                result.success(null)
            }
            "stopModelAnimation" -> {
                stopModelAnimation(call.int("instanceId"))
                result.success(null)
            }
            "createLight" -> {
                createLight(call)
                result.success(null)
            }
            "setLightPosition" -> {
                updateLight(call) { manager, instance ->
                    manager.setPosition(
                        instance,
                        call.float("x"),
                        call.float("y"),
                        call.float("z"),
                    )
                }
                result.success(null)
            }
            "setLightDirection" -> {
                updateLight(call) { manager, instance ->
                    manager.setDirection(
                        instance,
                        call.float("x"),
                        call.float("y"),
                        call.float("z"),
                    )
                }
                result.success(null)
            }
            "setLightIntensity" -> {
                updateLight(call) { manager, instance ->
                    manager.setIntensity(instance, call.float("intensity"))
                }
                result.success(null)
            }
            "destroyLight" -> {
                destroyLight(call.int("id"))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (disposed) {
            return
        }
        for (model in instances.values) {
            val animator = model.instance.animator
            val playback = model.animation ?: continue
            if (playback.animationIndex >= animator.animationCount) continue
            val duration = animator.getAnimationDuration(playback.animationIndex)
            if (duration <= 0.0f) continue
            val elapsed = playback.elapsedSeconds(frameTimeNanos)
            val animationTime = if (playback.loop) elapsed % duration else minOf(elapsed, duration)
            animator.applyAnimation(playback.animationIndex, animationTime)
            animator.updateBoneMatrices()
        }
        modelViewer.render(frameTimeNanos)
        choreographer.postFrameCallback(this)
    }

    override fun dispose() {
        disposed = true
        choreographer.removeFrameCallback(this)
        channel.setMethodCallHandler(null)
        lights.keys.toList().forEach(::destroyLight)
        instances.keys.toList().forEach(::destroyModelInstance)
        assets.values.forEach { assetLoader.destroyAsset(it.asset) }
        assets.clear()
        resourceLoader.destroy()
        materialProvider.destroyMaterials()
        materialProvider.destroy()
        assetLoader.destroy()
        modelViewer.destroy()
    }

    private fun loadModelAsset(context: Context, call: MethodCall) {
        val assetId = call.int("assetId")
        if (assets.containsKey(assetId)) return
        val bytes = context.assets.open(call.string("assetPath")).use { it.readBytes() }
        val asset = assetLoader.createAsset(ByteBuffer.wrap(bytes)) ?: return
        resourceLoader.loadResources(asset)
        assets[assetId] =
            NativeModelAsset(
                asset = asset,
                normalizedScale = call.float("normalizedScale"),
                animationIndex = call.nullableInt("animationIndex"),
            )
    }

    private fun createModelInstance(call: MethodCall) {
        val asset = assets[call.int("assetId")] ?: return
        val instanceId = call.int("instanceId")
        destroyModelInstance(instanceId)
        val instance = assetLoader.createInstance(asset.asset) ?: return
        val model =
            NativeModelInstance(
                asset = asset,
                instance = instance,
                animation =
                    call.nullableInt("animationIndex")?.let {
                        NativeAnimationPlayback(
                            animationIndex = it,
                            loop = call.boolean("loop", true),
                            speed = call.float("speed", 1.0f),
                            pausedAtNanos = if (call.boolean("paused")) System.nanoTime() else null,
                        )
                    },
            )
        instances[instanceId] = model
        modelViewer.scene.addEntities(instance.entities)
        updateModelTransform(model, call)
    }

    private fun updateModelTransform(call: MethodCall) {
        val model = instances[call.int("instanceId")] ?: return
        updateModelTransform(model, call)
    }

    private fun updateModelTransform(model: NativeModelInstance, call: MethodCall) {
        val box = model.asset.asset.boundingBox
        val extent = box.halfExtent
        val maxExtent = maxOf(extent[0], extent[1], extent[2]) * 2.0f
        val scale = model.asset.normalizedScale * 2.0f / maxExtent
        val center = box.center
        val qx = call.float("qx")
        val qy = call.float("qy")
        val qz = call.float("qz")
        val qw = call.float("qw")
        val m00 = 1 - 2 * (qy * qy + qz * qz)
        val m01 = 2 * (qx * qy - qz * qw)
        val m02 = 2 * (qx * qz + qy * qw)
        val m10 = 2 * (qx * qy + qz * qw)
        val m11 = 1 - 2 * (qx * qx + qz * qz)
        val m12 = 2 * (qy * qz - qx * qw)
        val m20 = 2 * (qx * qz - qy * qw)
        val m21 = 2 * (qy * qz + qx * qw)
        val m22 = 1 - 2 * (qx * qx + qy * qy)
        val targetX = call.float("x") * 0.12f
        val targetY = (call.float("y") - 0.65f) * 0.12f - 0.65f
        val targetZ = -4.0f - call.float("z") * 0.12f
        val tx = targetX - scale * (m00 * center[0] + m01 * center[1] + m02 * center[2])
        val ty = targetY - scale * (m10 * center[0] + m11 * center[1] + m12 * center[2])
        val tz = targetZ - scale * (m20 * center[0] + m21 * center[1] + m22 * center[2])
        val transform =
            floatArrayOf(
                scale * m00, scale * m10, scale * m20, 0.0f,
                scale * m01, scale * m11, scale * m21, 0.0f,
                scale * m02, scale * m12, scale * m22, 0.0f,
                tx, ty, tz, 1.0f,
            )
        val manager = modelViewer.engine.transformManager
        manager.setTransform(manager.getInstance(model.instance.root), transform)
    }

    private fun destroyModelInstance(id: Int) {
        val model = instances.remove(id) ?: return
        modelViewer.scene.removeEntities(model.instance.entities)
    }

    private fun getModelAnimations(id: Int): List<Map<String, Any>> {
        val animator = instances[id]?.instance?.animator ?: return emptyList()
        return (0 until animator.animationCount).map { index ->
            mapOf(
                "index" to index,
                "name" to animator.getAnimationName(index),
                "durationSeconds" to animator.getAnimationDuration(index).toDouble(),
            )
        }
    }

    private fun playModelAnimation(call: MethodCall) {
        val model = instances[call.int("instanceId")] ?: return
        model.animation =
            NativeAnimationPlayback(
                animationIndex = call.int("animationIndex"),
                loop = call.boolean("loop", true),
                speed = call.float("speed", 1.0f),
            )
    }

    private fun pauseModelAnimation(id: Int) {
        val playback = instances[id]?.animation ?: return
        if (playback.pausedAtNanos == null) {
            playback.pausedAtNanos = System.nanoTime()
        }
    }

    private fun resumeModelAnimation(id: Int) {
        val playback = instances[id]?.animation ?: return
        val pausedAtNanos = playback.pausedAtNanos ?: return
        playback.startedAtNanos += System.nanoTime() - pausedAtNanos
        playback.pausedAtNanos = null
    }

    private fun stopModelAnimation(id: Int) {
        instances[id]?.animation = null
    }

    private fun createLight(call: MethodCall) {
        val id = call.int("id")
        destroyLight(id)
        val entity = EntityManager.get().create()
        val type =
            if (call.int("type") == 1) LightManager.Type.POINT else LightManager.Type.SUN
        val builder =
            LightManager.Builder(type)
                .color(call.float("r"), call.float("g"), call.float("b"))
                .intensity(call.float("intensity"))
                .castShadows(call.boolean("castShadows"))
        if (type == LightManager.Type.POINT) {
            builder
                .position(call.float("x"), call.float("y"), call.float("z"))
                .falloff(call.float("falloffRadius"))
        } else {
            builder.direction(call.float("dx"), call.float("dy"), call.float("dz"))
        }
        builder.build(modelViewer.engine, entity)
        lights[id] = entity
        modelViewer.scene.addEntity(entity)
    }

    private fun updateLight(
        call: MethodCall,
        update: (LightManager, Int) -> Unit,
    ) {
        val entity = lights[call.int("id")] ?: return
        val manager = modelViewer.engine.lightManager
        update(manager, manager.getInstance(entity))
    }

    private fun destroyLight(id: Int) {
        val entity = lights.remove(id) ?: return
        modelViewer.scene.removeEntity(entity)
        modelViewer.engine.destroyEntity(entity)
        EntityManager.get().destroy(entity)
    }

    private fun MethodCall.int(name: String): Int = argument<Int>(name) ?: 0

    private fun MethodCall.nullableInt(name: String): Int? = argument<Int>(name)

    private fun MethodCall.float(name: String, fallback: Float = 0.0f): Float =
        argument<Number>(name)?.toFloat() ?: fallback

    private fun MethodCall.boolean(name: String, fallback: Boolean = false): Boolean =
        argument<Boolean>(name) ?: fallback

    private fun MethodCall.string(name: String): String = argument<String>(name) ?: ""

    private data class NativeModelAsset(
        val asset: FilamentAsset,
        val normalizedScale: Float,
        val animationIndex: Int?,
    )

    private data class NativeModelInstance(
        val asset: NativeModelAsset,
        val instance: FilamentInstance,
        var animation: NativeAnimationPlayback?,
    )

    private data class NativeAnimationPlayback(
        val animationIndex: Int,
        val loop: Boolean,
        val speed: Float,
        var startedAtNanos: Long = System.nanoTime(),
        var pausedAtNanos: Long? = null,
    ) {
        fun elapsedSeconds(frameTimeNanos: Long): Float {
            val currentNanos = pausedAtNanos ?: frameTimeNanos
            return (currentNanos - startedAtNanos) / 1_000_000_000.0f * speed
        }
    }

    companion object {
        init {
            System.loadLibrary("filament-jni")
            System.loadLibrary("filament-utils-jni")
            System.loadLibrary("gltfio-jni")
        }
    }
}
