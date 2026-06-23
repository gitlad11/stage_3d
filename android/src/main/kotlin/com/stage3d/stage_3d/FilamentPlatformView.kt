package com.stage3d.stage_3d

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.view.Choreographer
import android.view.TextureView
import com.google.android.filament.EntityManager
import com.google.android.filament.LightManager
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Skybox
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
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
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

class FilamentPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
) : PlatformView, MethodChannel.MethodCallHandler, Choreographer.FrameCallback {
    private val textureView = TextureView(context)
    private val modelViewer = ModelViewer(textureView, manipulator = null)
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
    private val meshes = mutableMapOf<Int, NativeTexturedMesh>()
    private var currentSkybox: Skybox? = null
    private var environmentReflectionIntensity = 0.9f
    private var cameraState = NativeCameraState()

    init {
        channel.setMethodCallHandler(this)
        setSkyboxColor(0.16f, 0.48f, 0.78f, 1.0f)
        modelViewer.scene.removeEntity(modelViewer.light)
        choreographer.postFrameCallback(this)
    }

    override fun getView() = textureView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resetView" -> {
                cameraState = NativeCameraState()
                applyCameraState()
                modelViewer.resetToDefaultState()
                result.success(null)
            }
            "setCamera" -> {
                setCamera(call)
                result.success(null)
            }
            "orbitCamera" -> {
                orbitCamera(call)
                result.success(null)
            }
            "moveCamera" -> {
                moveCamera(call)
                result.success(null)
            }
            "setEnvironment" -> {
                setEnvironment(call)
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
            "createTexturedMesh" -> {
                createTexturedMesh(call)
                result.success(null)
            }
            "destroyTexturedMesh" -> {
                destroyTexturedMesh(call.int("meshId"))
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
        applyCameraState()
        modelViewer.render(frameTimeNanos)
        choreographer.postFrameCallback(this)
    }

    override fun dispose() {
        disposed = true
        choreographer.removeFrameCallback(this)
        channel.setMethodCallHandler(null)
        lights.keys.toList().forEach(::destroyLight)
        meshes.keys.toList().forEach(::destroyTexturedMesh)
        instances.keys.toList().forEach(::destroyModelInstance)
        assets.values.forEach { assetLoader.destroyAsset(it.asset) }
        assets.clear()
        resourceLoader.destroy()
        materialProvider.destroyMaterials()
        materialProvider.destroy()
        currentSkybox?.let(modelViewer.engine::destroySkybox)
        currentSkybox = null
        assetLoader.destroy()
        modelViewer.destroy()
    }

    private fun loadModelAsset(context: Context, call: MethodCall) {
        val assetId = call.int("assetId")
        if (assets.containsKey(assetId)) return
        val assetPath = call.string("assetPath")
        val bytes = openAssetBytes(assetPath)
        val asset = assetLoader.createAsset(ByteBuffer.wrap(bytes)) ?: return
        resourceLoader.loadResources(asset)
        assets[assetId] =
            NativeModelAsset(
                asset = asset,
                normalizedScale = call.float("normalizedScale"),
                animationIndex = call.nullableInt("animationIndex"),
                verticalAnchor = NativeModelVerticalAnchor.from(call.string("verticalAnchor")),
            )
    }

    private fun orbitCamera(call: MethodCall) {
        cameraState =
            cameraState.copy(
                yaw = cameraState.yaw + call.float("deltaYaw"),
                pitch = (cameraState.pitch + call.float("deltaPitch")).coerceIn(-1.45f, 1.45f),
            )
        applyCameraState()
    }

    private fun moveCamera(call: MethodCall) {
        val right = call.float("deltaX") * 0.004f
        val forward = call.float("deltaY") * 0.004f
        val yawCos = cos(cameraState.yaw)
        val yawSin = sin(cameraState.yaw)
        cameraState =
            cameraState.copy(
                targetX = cameraState.targetX + yawCos * right + yawSin * forward,
                targetZ = cameraState.targetZ - yawSin * right + yawCos * forward,
            )
        applyCameraState()
    }

    private fun setCamera(call: MethodCall) {
        cameraState =
            NativeCameraState(
                targetX = call.float("targetX"),
                targetY = call.float("targetY"),
                targetZ = call.float("targetZ"),
                yaw = call.float("yaw"),
                pitch = call.float("pitch").coerceIn(-1.45f, 1.45f),
                distance = max(0.1f, call.float("distance", 4.0f)),
            )
        applyCameraState()
    }

    private fun applyCameraState() {
        val horizontal = cos(cameraState.pitch) * cameraState.distance
        val eyeX = cameraState.targetX + sin(cameraState.yaw) * horizontal
        val eyeY = cameraState.targetY + sin(cameraState.pitch) * cameraState.distance
        val eyeZ = cameraState.targetZ + cos(cameraState.yaw) * horizontal
        modelViewer.camera.lookAt(
            eyeX.toDouble(),
            eyeY.toDouble(),
            eyeZ.toDouble(),
            cameraState.targetX.toDouble(),
            cameraState.targetY.toDouble(),
            cameraState.targetZ.toDouble(),
            0.0,
            1.0,
            0.0,
        )
    }

    private fun createModelInstance(call: MethodCall) {
        val assetId = call.int("assetId")
        val asset = assets[assetId] ?: return
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
        val anchor =
            when (model.asset.verticalAnchor) {
                NativeModelVerticalAnchor.ORIGIN -> floatArrayOf(0.0f, 0.0f, 0.0f)
                NativeModelVerticalAnchor.CENTER -> center
                NativeModelVerticalAnchor.BOTTOM ->
                    floatArrayOf(center[0], center[1] - extent[1], center[2])
            }
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
        val targetY = (call.float("y") - 0.65f) * 0.12f - 0.15f
        val targetZ = -4.0f - call.float("z") * 0.12f
        val tx = targetX - scale * (m00 * anchor[0] + m01 * anchor[1] + m02 * anchor[2])
        val ty = targetY - scale * (m10 * anchor[0] + m11 * anchor[1] + m12 * anchor[2])
        val tz = targetZ - scale * (m20 * anchor[0] + m21 * anchor[1] + m22 * anchor[2])
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

    private fun createTexturedMesh(call: MethodCall) {
        val meshId = call.int("meshId")
        destroyTexturedMesh(meshId)
        val vertices = call.argument<List<Map<String, Any>>>("vertices") ?: return
        val indices = call.argument<List<Any>>("indices") ?: return
        val texture = call.argument<Map<String, Any>>("texture") ?: return
        val material = call.argument<Map<String, Any>>("material") ?: emptyMap<String, Any>()
        val glb = buildTexturedMeshGlb(vertices, indices, texture, material)
        val asset = assetLoader.createAsset(ByteBuffer.wrap(glb)) ?: return
        resourceLoader.loadResources(asset)
        val customMaterial = applyCustomMeshMaterial(asset, texture, material)
        meshes[meshId] = NativeTexturedMesh(asset, customMaterial)
        modelViewer.scene.addEntities(asset.entities)
    }

    private fun destroyTexturedMesh(id: Int) {
        val mesh = meshes.remove(id) ?: return
        modelViewer.scene.removeEntities(mesh.asset.entities)
        assetLoader.destroyAsset(mesh.asset)
        val customMaterial = mesh.customMaterial ?: return
        customMaterial.materialInstance?.let(modelViewer.engine::destroyMaterialInstance)
        customMaterial.material?.let(modelViewer.engine::destroyMaterial)
        customMaterial.textures.forEach(modelViewer.engine::destroyTexture)
    }

    private fun applyCustomMeshMaterial(
        asset: FilamentAsset,
        texture: Map<String, Any>,
        material: Map<String, Any>,
    ): NativeMeshMaterial? {
        val filamatAssetPath = material["filamatAssetPath"] as? String ?: return null
        val filamat = openAssetBytes(filamatAssetPath)
        val materialBuffer = ByteBuffer.allocateDirect(filamat.size)
        materialBuffer.put(filamat)
        materialBuffer.flip()
        val filamentMaterial =
            Material.Builder().payload(materialBuffer, filamat.size).build(modelViewer.engine)
        val materialInstance = filamentMaterial.createInstance()
        val materialTexture = createFilamentTexture(createTexturePng(texture))
        val materialTextures = mutableListOf(materialTexture)
        val sampler =
            TextureSampler(
                TextureSampler.MinFilter.LINEAR,
                TextureSampler.MagFilter.LINEAR,
                TextureSampler.WrapMode.REPEAT,
            )

        materialInstance.setParameter("albedo", materialTexture, sampler)
        val textureUniforms = material["textureUniforms"] as? Map<*, *> ?: emptyMap<Any, Any>()
        for ((name, textureMessage) in textureUniforms) {
            val uniformName = name as? String ?: continue
            val uniformTexture = textureMessage as? Map<String, Any> ?: continue
            val filamentTexture = createFilamentTexture(createTexturePng(uniformTexture))
            materialTextures += filamentTexture
            materialInstance.setParameter(uniformName, filamentTexture, sampler)
        }
        materialInstance.setParameter("roughness", number(material["roughnessFactor"]).toFloat())
        materialInstance.setParameter("metallic", number(material["metallicFactor"]).toFloat())
        materialInstance.setParameter("tint", 1.0f, 1.0f, 1.0f, 1.0f)
        materialInstance.setParameter("reflectance", environmentReflectionIntensity)
        materialInstance.setParameter("windStrength", 0.0f)
        materialInstance.setParameter("windScale", 1.0f)
        applyShaderUniforms(materialInstance, material["shader"] as? Map<*, *>)

        val renderableManager = modelViewer.engine.renderableManager
        for (entity in asset.entities) {
            if (!renderableManager.hasComponent(entity)) {
                continue
            }
            val instance = renderableManager.getInstance(entity)
            for (primitive in 0 until renderableManager.getPrimitiveCount(instance)) {
                renderableManager.setMaterialInstanceAt(instance, primitive, materialInstance)
            }
        }
        return NativeMeshMaterial(
            material = filamentMaterial,
            materialInstance = materialInstance,
            textures = materialTextures,
        )
    }

    private fun setEnvironment(call: MethodCall) {
        setSkyboxColor(
            call.float("skyR", 0.16f),
            call.float("skyG", 0.48f),
            call.float("skyB", 0.78f),
            call.float("skyA", 1.0f),
        )
        environmentReflectionIntensity = call.float("reflectionIntensity", 0.9f)
        updateMeshReflectance(environmentReflectionIntensity)
    }

    private fun setSkyboxColor(r: Float, g: Float, b: Float, a: Float) {
        val previous = currentSkybox
        val skybox = Skybox.Builder().color(r, g, b, a).build(modelViewer.engine)
        modelViewer.scene.skybox = skybox
        currentSkybox = skybox
        previous?.let(modelViewer.engine::destroySkybox)
    }

    private fun updateMeshReflectance(reflectance: Float) {
        for (mesh in meshes.values) {
            mesh.customMaterial?.materialInstance?.setParameter("reflectance", reflectance)
        }
    }

    private fun applyShaderUniforms(
        materialInstance: MaterialInstance,
        shader: Map<*, *>?,
    ) {
        val uniforms = shader?.get("uniforms") as? List<*> ?: return
        for (uniform in uniforms) {
            val item = uniform as? Map<*, *> ?: continue
            val name = item["name"] as? String ?: continue
            when (item["type"] as? String) {
                "float" -> materialInstance.setParameter(name, number(item["value"]).toFloat())
                "bool" -> materialInstance.setParameter(name, item["value"] as? Boolean ?: false)
                "color" -> {
                    val argb = number(item["value"]).toInt()
                    materialInstance.setParameter(
                        name,
                        ((argb ushr 16) and 0xff) / 255.0f,
                        ((argb ushr 8) and 0xff) / 255.0f,
                        (argb and 0xff) / 255.0f,
                        ((argb ushr 24) and 0xff) / 255.0f,
                    )
                }
            }
        }
    }

    private fun createFilamentTexture(png: ByteArray): Texture {
        val source = BitmapFactory.decodeByteArray(png, 0, png.size)
        val bitmap =
            if (source.config == Bitmap.Config.ARGB_8888) {
                source
            } else {
                val copy = source.copy(Bitmap.Config.ARGB_8888, false)
                source.recycle()
                copy
            }
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        bitmap.recycle()

        val buffer = ByteBuffer.allocateDirect(pixels.size * 4)
        for (pixel in pixels) {
            buffer.put(((pixel ushr 16) and 0xff).toByte())
            buffer.put(((pixel ushr 8) and 0xff).toByte())
            buffer.put((pixel and 0xff).toByte())
            buffer.put(((pixel ushr 24) and 0xff).toByte())
        }
        buffer.flip()

        val filamentTexture =
            Texture.Builder()
                .width(width)
                .height(height)
                .levels(1)
                .sampler(Texture.Sampler.SAMPLER_2D)
                .format(Texture.InternalFormat.SRGB8_A8)
                .build(modelViewer.engine)
        filamentTexture.setImage(
            modelViewer.engine,
            0,
            Texture.PixelBufferDescriptor(buffer, Texture.Format.RGBA, Texture.Type.UBYTE),
        )
        return filamentTexture
    }

    private fun buildTexturedMeshGlb(
        vertices: List<Map<String, Any>>,
        indices: List<Any>,
        texture: Map<String, Any>,
        material: Map<String, Any>,
    ): ByteArray {
        val positions = mutableListOf<Float>()
        val normals = mutableListOf<Float>()
        val uvs = mutableListOf<Float>()
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var minZ = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        var maxZ = Float.NEGATIVE_INFINITY
        for (vertex in vertices) {
            val localX = number(vertex["x"]).toFloat()
            val localY = number(vertex["y"]).toFloat()
            val localZ = number(vertex["z"]).toFloat()
            val x = localX * 0.25f - 0.75f
            val y = localY * 0.25f - 0.75f
            val z = -4.0f - localZ * 0.25f
            positions += x
            positions += y
            positions += z
            normals += number(vertex["nx"]).toFloat()
            normals += number(vertex["ny"]).toFloat()
            normals += number(vertex["nz"]).toFloat()
            uvs += number(vertex["u"]).toFloat()
            uvs += number(vertex["v"]).toFloat()
            minX = minOf(minX, x)
            minY = minOf(minY, y)
            minZ = minOf(minZ, z)
            maxX = maxOf(maxX, x)
            maxY = maxOf(maxY, y)
            maxZ = maxOf(maxZ, z)
        }

        val positionOffset = 0
        val positionBytes = positions.size * 4
        val normalOffset = align4(positionOffset + positionBytes)
        val normalBytes = normals.size * 4
        val uvOffset = align4(normalOffset + normalBytes)
        val uvBytes = uvs.size * 4
        val indexOffset = align4(uvOffset + uvBytes)
        val useShortIndices = vertices.size <= 65535
        val indexBytes = indices.size * if (useShortIndices) 2 else 4
        val imageOffset = align4(indexOffset + indexBytes)
        val png = createTexturePng(texture)
        val binLength = align4(imageOffset + png.size)
        val bin = ByteBuffer.allocate(binLength).order(ByteOrder.LITTLE_ENDIAN)
        bin.position(positionOffset)
        positions.forEach(bin::putFloat)
        bin.position(normalOffset)
        normals.forEach(bin::putFloat)
        bin.position(uvOffset)
        uvs.forEach(bin::putFloat)
        bin.position(indexOffset)
        if (useShortIndices) {
            indices.forEach { bin.putShort(number(it).toInt().toShort()) }
        } else {
            indices.forEach { bin.putInt(number(it).toInt()) }
        }
        bin.position(imageOffset)
        bin.put(png)
        val baseColor = colorFactor(number(material["baseColor"]).toInt())
        val metallicFactor = number(material["metallicFactor"]).toFloat()
        val roughnessFactor = number(material["roughnessFactor"]).toFloat()
        val doubleSided = material["doubleSided"] as? Boolean ?: true

        val json =
            """
            {
              "asset":{"version":"2.0","generator":"stage_3d TexturedMeshPrototype"},
              "scene":0,
              "scenes":[{"nodes":[0]}],
              "nodes":[{"mesh":0}],
              "meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"material":0}]}],
              "materials":[{"doubleSided":$doubleSided,"pbrMetallicRoughness":{"baseColorFactor":$baseColor,"baseColorTexture":{"index":0},"metallicFactor":$metallicFactor,"roughnessFactor":$roughnessFactor}}],
              "textures":[{"sampler":0,"source":0}],
              "samplers":[{"magFilter":9728,"minFilter":9728,"wrapS":10497,"wrapT":10497}],
              "images":[{"mimeType":"image/png","bufferView":4}],
              "buffers":[{"byteLength":$binLength}],
              "bufferViews":[
                {"buffer":0,"byteOffset":$positionOffset,"byteLength":$positionBytes,"target":34962},
                {"buffer":0,"byteOffset":$normalOffset,"byteLength":$normalBytes,"target":34962},
                {"buffer":0,"byteOffset":$uvOffset,"byteLength":$uvBytes,"target":34962},
                {"buffer":0,"byteOffset":$indexOffset,"byteLength":$indexBytes,"target":34963},
                {"buffer":0,"byteOffset":$imageOffset,"byteLength":${png.size}}
              ],
              "accessors":[
                {"bufferView":0,"componentType":5126,"count":${vertices.size},"type":"VEC3","min":[$minX,$minY,$minZ],"max":[$maxX,$maxY,$maxZ]},
                {"bufferView":1,"componentType":5126,"count":${vertices.size},"type":"VEC3"},
                {"bufferView":2,"componentType":5126,"count":${vertices.size},"type":"VEC2"},
                {"bufferView":3,"componentType":${if (useShortIndices) 5123 else 5125},"count":${indices.size},"type":"SCALAR"}
              ]
            }
            """.trimIndent()
        return buildGlb(json, bin.array())
    }

    private fun createTexturePng(texture: Map<String, Any>): ByteArray {
        if (texture["kind"] == "asset") {
            val assetPath = texture["assetPath"] as? String
            if (assetPath != null) {
                return createAssetTexturePng(assetPath, texture)
            }
        }
        return createCheckerTexturePng(texture)
    }

    private fun openAssetBytes(assetPath: String): ByteArray =
        openAssetStream(assetPath).use { it.readBytes() }

    private fun openAssetStream(assetPath: String) =
        assetPathCandidates(assetPath).firstNotNullOfOrNull { candidate ->
            try {
                context.assets.open(candidate)
            } catch (_: FileNotFoundException) {
                null
            }
        } ?: throw FileNotFoundException(
            "Could not find asset '$assetPath'. Tried: ${assetPathCandidates(assetPath).joinToString()}",
        )

    private fun assetPathCandidates(assetPath: String): List<String> {
        val normalized = assetPath.trimStart('/')
        return listOf(
            normalized,
            "flutter_assets/$normalized",
            "flutter_assets/assets/$normalized",
        ).distinct()
    }

    private fun createAssetTexturePng(assetPath: String, texture: Map<String, Any>): ByteArray {
        val source = openAssetStream(assetPath).use(BitmapFactory::decodeStream)
        val region = texture["sourceRegion"] as? Map<*, *>
        val left = ((region?.get("left") as? Number)?.toFloat() ?: 0.0f) * source.width
        val top = ((region?.get("top") as? Number)?.toFloat() ?: 0.0f) * source.height
        val right = ((region?.get("right") as? Number)?.toFloat() ?: 1.0f) * source.width
        val bottom = ((region?.get("bottom") as? Number)?.toFloat() ?: 1.0f) * source.height
        val cropLeft = left.toInt().coerceIn(0, source.width - 1)
        val cropTop = top.toInt().coerceIn(0, source.height - 1)
        val cropRight = right.toInt().coerceIn(cropLeft + 1, source.width)
        val cropBottom = bottom.toInt().coerceIn(cropTop + 1, source.height)
        val tile = Bitmap.createBitmap(
            source,
            cropLeft,
            cropTop,
            cropRight - cropLeft,
            cropBottom - cropTop,
        )
        source.recycle()

        val repeatU = max(1, ceil(number(texture["repeatU"]).toDouble()).toInt())
        val repeatV = max(1, ceil(number(texture["repeatV"]).toDouble()).toInt())
        val bitmap = Bitmap.createBitmap(
            tile.width * repeatU,
            tile.height * repeatV,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        for (y in 0 until repeatV) {
            for (x in 0 until repeatU) {
                canvas.drawBitmap(
                    tile,
                    null,
                    Rect(
                        x * tile.width,
                        y * tile.height,
                        (x + 1) * tile.width,
                        (y + 1) * tile.height,
                    ),
                    paint,
                )
            }
        }
        tile.recycle()
        return encodePng(bitmap)
    }

    private fun createCheckerTexturePng(texture: Map<String, Any>): ByteArray {
        val primary = number(texture["primaryColor"]).toInt()
        val secondary = number(texture["secondaryColor"]).toInt()
        val repeatU = max(1, ceil(number(texture["repeatU"]).toDouble()).toInt())
        val repeatV = max(1, ceil(number(texture["repeatV"]).toDouble()).toInt())
        val tileSize = 16
        val width = repeatU * tileSize
        val height = repeatV * tileSize
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val tile = x / tileSize + y / tileSize
                bitmap.setPixel(x, y, if (tile % 2 == 0) primary else secondary)
            }
        }
        return encodePng(bitmap)
    }

    private fun encodePng(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        bitmap.recycle()
        return output.toByteArray()
    }

    private fun buildGlb(json: String, bin: ByteArray): ByteArray {
        val jsonBytes = json.toByteArray(Charsets.UTF_8)
        val jsonLength = align4(jsonBytes.size)
        val binLength = align4(bin.size)
        val totalLength = 12 + 8 + jsonLength + 8 + binLength
        val glb = ByteBuffer.allocate(totalLength).order(ByteOrder.LITTLE_ENDIAN)
        glb.putInt(0x46546C67)
        glb.putInt(2)
        glb.putInt(totalLength)
        glb.putInt(jsonLength)
        glb.putInt(0x4E4F534A)
        glb.put(jsonBytes)
        repeat(jsonLength - jsonBytes.size) { glb.put(0x20.toByte()) }
        glb.putInt(binLength)
        glb.putInt(0x004E4942)
        glb.put(bin)
        repeat(binLength - bin.size) { glb.put(0) }
        return glb.array()
    }

    private fun align4(value: Int): Int = (value + 3) and -4

    private fun number(value: Any?): Number = value as? Number ?: 0

    private fun colorFactor(argb: Int): String {
        val a = ((argb ushr 24) and 0xff) / 255.0f
        val r = ((argb ushr 16) and 0xff) / 255.0f
        val g = ((argb ushr 8) and 0xff) / 255.0f
        val b = (argb and 0xff) / 255.0f
        return "[$r,$g,$b,$a]"
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
        val verticalAnchor: NativeModelVerticalAnchor,
    )

    private enum class NativeModelVerticalAnchor {
        ORIGIN,
        CENTER,
        BOTTOM,
        ;

        companion object {
            fun from(value: String): NativeModelVerticalAnchor =
                when (value.lowercase()) {
                    "origin" -> ORIGIN
                    "bottom" -> BOTTOM
                    else -> CENTER
                }
        }
    }

    private data class NativeModelInstance(
        val asset: NativeModelAsset,
        val instance: FilamentInstance,
        var animation: NativeAnimationPlayback?,
    )

    private data class NativeTexturedMesh(
        val asset: FilamentAsset,
        val customMaterial: NativeMeshMaterial?,
    )

    private data class NativeMeshMaterial(
        val material: Material?,
        val materialInstance: MaterialInstance?,
        val textures: List<Texture>,
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

    private data class NativeCameraState(
        val targetX: Float = 0.0f,
        val targetY: Float = 0.0f,
        val targetZ: Float = 0.0f,
        val yaw: Float = 0.0f,
        val pitch: Float = 0.0f,
        val distance: Float = 4.0f,
    )

    companion object {
        init {
            System.loadLibrary("filament-jni")
            System.loadLibrary("filament-utils-jni")
            System.loadLibrary("gltfio-jni")
        }
    }
}
