package com.example.jolt_physics_dart

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
import com.google.android.filament.View
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
import kotlin.math.max

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
    private val nativeEngine = NativeStageEngine()
    private var disposed = false
    private val lights = mutableMapOf<Int, Int>()
    private val assets = mutableMapOf<Int, NativeModelAsset>()
    private val instances = mutableMapOf<Int, NativeModelInstance>()
    private val meshes = mutableMapOf<Int, NativeTexturedMesh>()
    private var currentSkybox: Skybox? = null
    private var environmentReflectionIntensity = 0.9f

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
                nativeEngine.resetCamera()
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
            "setRenderOptions" -> {
                setRenderOptions(call)
                result.success(null)
            }
            "loadModelAsset" -> {
                loadModelAsset(context, call)
                result.success(null)
            }
            "unloadModelAsset" -> {
                unloadModelAsset(call.int("assetId"))
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
                updateLight(call) { id ->
                    nativeEngine.setLightPosition(
                        id,
                        call.float("x"),
                        call.float("y"),
                        call.float("z"),
                    )
                }
                result.success(null)
            }
            "setLightDirection" -> {
                updateLight(call) { id ->
                    nativeEngine.setLightDirection(
                        id,
                        call.float("x"),
                        call.float("y"),
                        call.float("z"),
                    )
                }
                result.success(null)
            }
            "setLightIntensity" -> {
                updateLight(call) { id ->
                    nativeEngine.setLightIntensity(id, call.float("intensity"))
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
        for ((instanceId, model) in instances) {
            val animator = model.instance.animator
            val animationIndex = nativeEngine.modelAnimationIndex(instanceId)
            if (animationIndex < 0 || animationIndex >= animator.animationCount) continue
            val duration = animator.getAnimationDuration(animationIndex)
            if (duration <= 0.0f) continue
            val animationTime =
                nativeEngine.sampleModelAnimationTime(instanceId, frameTimeNanos, duration)
            if (animationTime.isNaN()) continue
            animator.applyAnimation(animationIndex, animationTime)
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
        meshes.keys.toList().forEach(::destroyTexturedMesh)
        instances.keys.toList().forEach(::destroyModelInstance)
        assets.keys.toList().forEach(::unloadModelAsset)
        resourceLoader.destroy()
        materialProvider.destroyMaterials()
        materialProvider.destroy()
        currentSkybox?.let(modelViewer.engine::destroySkybox)
        currentSkybox = null
        nativeEngine.close()
        assetLoader.destroy()
        modelViewer.destroy()
    }

    private fun loadModelAsset(context: Context, call: MethodCall) {
        val assetId = call.int("assetId")
        if (assets.containsKey(assetId)) return
        val assetPath = call.string("assetPath")
        val bytes =
            if (assetPath.substringAfterLast('.', "").lowercase() == "obj") {
                buildObjModelGlb(assetPath, String(openAssetBytes(assetPath), Charsets.UTF_8))
            } else {
                openAssetBytes(assetPath)
            }
        val asset = assetLoader.createAsset(ByteBuffer.wrap(bytes)) ?: return
        resourceLoader.loadResources(asset)
        val bounds = asset.boundingBox
        nativeEngine.registerModelAsset(
            assetId,
            call.float("normalizedScale"),
            NativeModelVerticalAnchor.from(call.string("verticalAnchor")).nativeValue,
            bounds.center,
            bounds.halfExtent,
        )
        assets[assetId] = NativeModelAsset(asset)
    }

    private fun unloadModelAsset(assetId: Int) {
        val asset = assets[assetId] ?: return
        if (!nativeEngine.removeModelAsset(assetId)) return
        assets.remove(assetId)
        assetLoader.destroyAsset(asset.asset)
    }

    private fun orbitCamera(call: MethodCall) {
        nativeEngine.orbitCamera(call.float("deltaYaw"), call.float("deltaPitch"))
        applyCameraState()
    }

    private fun moveCamera(call: MethodCall) {
        nativeEngine.moveCamera(call.float("deltaX"), call.float("deltaY"))
        applyCameraState()
    }

    private fun setCamera(call: MethodCall) {
        nativeEngine.setCamera(
            call.float("targetX"),
            call.float("targetY"),
            call.float("targetZ"),
            call.float("yaw"),
            call.float("pitch"),
            call.float("distance", 4.0f),
        )
        applyCameraState()
    }

    private fun applyCameraState() {
        val camera = nativeEngine.camera()
        modelViewer.camera.lookAt(
            camera[0].toDouble(),
            camera[1].toDouble(),
            camera[2].toDouble(),
            camera[3].toDouble(),
            camera[4].toDouble(),
            camera[5].toDouble(),
            camera[6].toDouble(),
            camera[7].toDouble(),
            camera[8].toDouble(),
        )
    }

    private fun createModelInstance(call: MethodCall) {
        val assetId = call.int("assetId")
        val asset = assets[assetId] ?: return
        val instanceId = call.int("instanceId")
        destroyModelInstance(instanceId)
        if (!nativeEngine.createModelInstance(instanceId, assetId)) return
        val instance =
            assetLoader.createInstance(asset.asset)
                ?: run {
                    nativeEngine.removeModelInstance(instanceId)
                    return
                }
        val model = NativeModelInstance(instance)
        instances[instanceId] = model
        call.nullableInt("animationIndex")?.let { animationIndex ->
            nativeEngine.playModelAnimation(
                instanceId,
                animationIndex,
                call.boolean("loop", true),
                call.float("speed", 1.0f),
                System.nanoTime(),
                call.boolean("paused"),
            )
        }
        modelViewer.scene.addEntities(instance.entities)
        updateModelTransform(instanceId, model, call)
    }

    private fun updateModelTransform(call: MethodCall) {
        val instanceId = call.int("instanceId")
        val model = instances[instanceId] ?: return
        updateModelTransform(instanceId, model, call)
    }

    private fun updateModelTransform(
        instanceId: Int,
        model: NativeModelInstance,
        call: MethodCall,
    ) {
        nativeEngine.setModelTransform(
            instanceId,
            call.float("x"),
            call.float("y"),
            call.float("z"),
            call.float("qx"),
            call.float("qy"),
            call.float("qz"),
            call.float("qw"),
        )
        nativeEngine.fillModelMatrix(instanceId, model.transform)
        val manager = modelViewer.engine.transformManager
        manager.setTransform(manager.getInstance(model.instance.root), model.transform)
    }

    private fun destroyModelInstance(id: Int) {
        nativeEngine.removeModelInstance(id)
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
        nativeEngine.setEnvironment(
            call.float("skyR", 0.16f),
            call.float("skyG", 0.48f),
            call.float("skyB", 0.78f),
            call.float("skyA", 1.0f),
            call.float("ambientIntensity", 30000.0f),
            call.float("reflectionIntensity", 0.9f),
        )
        val environment = nativeEngine.environment()
        setSkyboxColor(
            environment[0],
            environment[1],
            environment[2],
            environment[3],
        )
        environmentReflectionIntensity = environment[5]
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

    private fun setRenderOptions(call: MethodCall) {
        val view = modelViewer.view
        view.setPostProcessingEnabled(call.boolean("postProcessing", true))
        view.setShadowingEnabled(call.boolean("shadows", true))
        view.setShadowType(shadowType(call.string("shadowType")))

        val ambientOcclusion = call.map("ambientOcclusion")
        val aoOptions = View.AmbientOcclusionOptions()
        aoOptions.enabled = ambientOcclusion.boolean("enabled")
        aoOptions.radius = ambientOcclusion.float("radius", 0.3f)
        aoOptions.intensity = ambientOcclusion.float("intensity", 1.0f)
        aoOptions.power = ambientOcclusion.float("power", 1.0f)
        aoOptions.quality = quality(ambientOcclusion.string("quality"))
        view.ambientOcclusionOptions = aoOptions

        val bloom = call.map("bloom")
        val bloomOptions = View.BloomOptions()
        bloomOptions.enabled = bloom.boolean("enabled")
        bloomOptions.strength = bloom.float("strength", 0.1f)
        bloomOptions.resolution = bloom.int("resolution", 384)
        bloomOptions.levels = bloom.int("levels", 6)
        bloomOptions.threshold = bloom.boolean("threshold", true)
        bloomOptions.quality = quality(bloom.string("quality"))
        view.bloomOptions = bloomOptions

        val reflections = call.map("screenSpaceReflections")
        val reflectionOptions = View.ScreenSpaceReflectionsOptions()
        reflectionOptions.enabled = reflections.boolean("enabled")
        reflectionOptions.thickness = reflections.float("thickness", 0.1f)
        reflectionOptions.bias = reflections.float("bias", 0.01f)
        reflectionOptions.maxDistance = reflections.float("maxDistance", 3.0f)
        reflectionOptions.stride = reflections.float("stride", 2.0f)
        view.screenSpaceReflectionsOptions = reflectionOptions

        val msaa = call.map("msaa")
        val msaaOptions = View.MultiSampleAntiAliasingOptions()
        msaaOptions.enabled = msaa.boolean("enabled")
        msaaOptions.sampleCount = msaa.int("sampleCount", 4)
        view.multiSampleAntiAliasingOptions = msaaOptions
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

    private fun buildObjModelGlb(assetPath: String, source: String): ByteArray {
        val positions = mutableListOf<ObjVec3>()
        val texcoords = mutableListOf<ObjVec2>()
        val normals = mutableListOf<ObjVec3>()
        val materialLibraries = mutableListOf<String>()
        val meshes = linkedMapOf<String, ObjMeshData>()
        var currentMaterialName = ""

        fun currentMesh(): ObjMeshData =
            meshes.getOrPut(currentMaterialName) { ObjMeshData(currentMaterialName) }

        for (rawLine in source.lineSequence()) {
            val line = rawLine.substringBefore('#').trim()
            if (line.isEmpty()) continue
            val parts = line.split(Regex("\\s+"))
            when (parts.firstOrNull()) {
                "mtllib" -> {
                    materialLibraries += parts.drop(1).joinToString(" ")
                }
                "usemtl" -> {
                    currentMaterialName = parts.drop(1).joinToString(" ")
                }
                "v" -> {
                    if (parts.size < 4) continue
                    positions += ObjVec3(
                        parts[1].toFloatOrNull() ?: 0.0f,
                        parts[2].toFloatOrNull() ?: 0.0f,
                        parts[3].toFloatOrNull() ?: 0.0f,
                    )
                }
                "vt" -> {
                    if (parts.size < 3) continue
                    texcoords += ObjVec2(
                        parts[1].toFloatOrNull() ?: 0.0f,
                        parts[2].toFloatOrNull() ?: 0.0f,
                    )
                }
                "vn" -> {
                    if (parts.size < 4) continue
                    normals += normalize(
                        ObjVec3(
                            parts[1].toFloatOrNull() ?: 0.0f,
                            parts[2].toFloatOrNull() ?: 0.0f,
                            parts[3].toFloatOrNull() ?: 0.0f,
                        ),
                    )
                }
                "f" -> {
                    val refs = parts.drop(1).mapNotNull {
                        parseObjFaceRef(it, positions.size, texcoords.size, normals.size)
                    }
                    if (refs.size < 3) continue
                    for (index in 1 until refs.lastIndex) {
                        appendObjTriangle(
                            refs[0],
                            refs[index],
                            refs[index + 1],
                            positions,
                            texcoords,
                            normals,
                            currentMesh(),
                        )
                    }
                }
            }
        }

        val renderableMeshes =
            meshes.values.filter { it.positions.isNotEmpty() && it.indices.isNotEmpty() }
        if (renderableMeshes.isEmpty()) {
            throw IllegalArgumentException("OBJ asset does not contain renderable faces.")
        }

        val loadedMaterials = loadObjMaterials(assetPath, materialLibraries)
        val fallbackMaterial =
            if (renderableMeshes.all { it.materialName.isEmpty() } && loadedMaterials.isNotEmpty()) {
                loadedMaterials.values.first()
            } else {
                ObjMaterial()
            }
        val materials = renderableMeshes.map { mesh ->
            loadedMaterials[mesh.materialName] ?: fallbackMaterial
        }
        val materialJson = materials.joinToString(",") { it.toGltfJson() }

        var offset = 0
        val buffers = renderableMeshes.map { mesh ->
            val positionOffset = align4(offset)
            val positionBytes = mesh.positions.size * 4
            val normalOffset = align4(positionOffset + positionBytes)
            val normalBytes = mesh.normals.size * 4
            val uvOffset = align4(normalOffset + normalBytes)
            val uvBytes = mesh.texcoords.size * 4
            val indexOffset = align4(uvOffset + uvBytes)
            val useShortIndices = mesh.vertexCount <= 65535
            val indexBytes = mesh.indices.size * if (useShortIndices) 2 else 4
            offset = indexOffset + indexBytes
            ObjPrimitiveBuffer(
                mesh = mesh,
                positionOffset = positionOffset,
                positionBytes = positionBytes,
                normalOffset = normalOffset,
                normalBytes = normalBytes,
                uvOffset = uvOffset,
                uvBytes = uvBytes,
                indexOffset = indexOffset,
                indexBytes = indexBytes,
                useShortIndices = useShortIndices,
            )
        }
        val binLength = align4(offset)
        val bin = ByteBuffer.allocate(binLength).order(ByteOrder.LITTLE_ENDIAN)
        for (buffer in buffers) {
            bin.position(buffer.positionOffset)
            buffer.mesh.positions.forEach(bin::putFloat)
            bin.position(buffer.normalOffset)
            buffer.mesh.normals.forEach(bin::putFloat)
            bin.position(buffer.uvOffset)
            buffer.mesh.texcoords.forEach(bin::putFloat)
            bin.position(buffer.indexOffset)
            if (buffer.useShortIndices) {
                buffer.mesh.indices.forEach { bin.putShort(it.toShort()) }
            } else {
                buffer.mesh.indices.forEach(bin::putInt)
            }
        }

        val primitivesJson =
            buffers.mapIndexed { index, _ ->
                val positionAccessor = index * 4
                val normalAccessor = positionAccessor + 1
                val uvAccessor = positionAccessor + 2
                val indexAccessor = positionAccessor + 3
                """{"attributes":{"POSITION":$positionAccessor,"NORMAL":$normalAccessor,"TEXCOORD_0":$uvAccessor},"indices":$indexAccessor,"material":$index}"""
            }.joinToString(",")
        val bufferViewsJson =
            buffers.flatMap { buffer ->
                listOf(
                    """{"buffer":0,"byteOffset":${buffer.positionOffset},"byteLength":${buffer.positionBytes},"target":34962}""",
                    """{"buffer":0,"byteOffset":${buffer.normalOffset},"byteLength":${buffer.normalBytes},"target":34962}""",
                    """{"buffer":0,"byteOffset":${buffer.uvOffset},"byteLength":${buffer.uvBytes},"target":34962}""",
                    """{"buffer":0,"byteOffset":${buffer.indexOffset},"byteLength":${buffer.indexBytes},"target":34963}""",
                )
            }.joinToString(",")
        val accessorsJson =
            buffers.flatMap { buffer ->
                val mesh = buffer.mesh
                listOf(
                    """{"bufferView":${buffers.indexOf(buffer) * 4},"componentType":5126,"count":${mesh.vertexCount},"type":"VEC3","min":[${mesh.minX},${mesh.minY},${mesh.minZ}],"max":[${mesh.maxX},${mesh.maxY},${mesh.maxZ}]}""",
                    """{"bufferView":${buffers.indexOf(buffer) * 4 + 1},"componentType":5126,"count":${mesh.vertexCount},"type":"VEC3"}""",
                    """{"bufferView":${buffers.indexOf(buffer) * 4 + 2},"componentType":5126,"count":${mesh.vertexCount},"type":"VEC2"}""",
                    """{"bufferView":${buffers.indexOf(buffer) * 4 + 3},"componentType":${if (buffer.useShortIndices) 5123 else 5125},"count":${mesh.indices.size},"type":"SCALAR"}""",
                )
            }.joinToString(",")

        val json =
            """
            {
              "asset":{"version":"2.0","generator":"stage_3d OBJ runtime loader"},
              "scene":0,
              "scenes":[{"nodes":[0]}],
              "nodes":[{"mesh":0}],
              "meshes":[{"primitives":[$primitivesJson]}],
              "materials":[$materialJson],
              "buffers":[{"byteLength":$binLength}],
              "bufferViews":[$bufferViewsJson],
              "accessors":[$accessorsJson]
            }
            """.trimIndent()
        return buildGlb(json, bin.array())
    }

    private fun loadObjMaterials(
        objAssetPath: String,
        materialLibraries: List<String>,
    ): Map<String, ObjMaterial> {
        val directory = objAssetPath.substringBeforeLast('/', "")
        val materials = linkedMapOf<String, ObjMaterial>()
        for (library in materialLibraries) {
            val materialPath =
                if (directory.isEmpty() || library.contains('/')) {
                    library
                } else {
                    "$directory/$library"
                }
            val source =
                try {
                    String(openAssetBytes(materialPath), Charsets.UTF_8)
                } catch (_: FileNotFoundException) {
                    continue
                }
            materials += parseObjMtl(source)
        }
        return materials
    }

    private fun parseObjMtl(source: String): Map<String, ObjMaterial> {
        val materials = linkedMapOf<String, ObjMaterial>()
        var current: ObjMaterial? = null
        for (rawLine in source.lineSequence()) {
            val line = rawLine.substringBefore('#').trim()
            if (line.isEmpty()) continue
            val parts = line.split(Regex("\\s+"))
            when (parts.firstOrNull()) {
                "newmtl" -> {
                    current = ObjMaterial(name = parts.drop(1).joinToString(" "))
                    materials[current.name] = current
                }
                "Kd" -> {
                    val material = current ?: continue
                    if (parts.size >= 4) {
                        material.baseColor[0] = parts[1].toFloatOrNull() ?: material.baseColor[0]
                        material.baseColor[1] = parts[2].toFloatOrNull() ?: material.baseColor[1]
                        material.baseColor[2] = parts[3].toFloatOrNull() ?: material.baseColor[2]
                    }
                }
                "d" -> {
                    val material = current ?: continue
                    material.baseColor[3] = parts.getOrNull(1)?.toFloatOrNull() ?: material.baseColor[3]
                }
                "Tr" -> {
                    val material = current ?: continue
                    val transparency = parts.getOrNull(1)?.toFloatOrNull() ?: 0.0f
                    material.baseColor[3] = (1.0f - transparency).coerceIn(0.0f, 1.0f)
                }
                "Ns" -> {
                    val material = current ?: continue
                    val shininess = parts.getOrNull(1)?.toFloatOrNull() ?: 0.0f
                    material.roughness = (1.0f - shininess.coerceIn(0.0f, 1000.0f) / 1000.0f)
                        .coerceIn(0.05f, 1.0f)
                }
            }
        }
        return materials
    }

    private fun appendObjTriangle(
        first: ObjFaceRef,
        second: ObjFaceRef,
        third: ObjFaceRef,
        positions: List<ObjVec3>,
        texcoords: List<ObjVec2>,
        normals: List<ObjVec3>,
        mesh: ObjMeshData,
    ) {
        if (first.position !in positions.indices ||
            second.position !in positions.indices ||
            third.position !in positions.indices
        ) {
            return
        }
        val faceNormal = triangleNormal(
            positions[first.position],
            positions[second.position],
            positions[third.position],
        )
        appendObjVertex(first, positions, texcoords, normals, faceNormal, mesh)
        appendObjVertex(second, positions, texcoords, normals, faceNormal, mesh)
        appendObjVertex(third, positions, texcoords, normals, faceNormal, mesh)
    }

    private fun appendObjVertex(
        ref: ObjFaceRef,
        positions: List<ObjVec3>,
        texcoords: List<ObjVec2>,
        normals: List<ObjVec3>,
        fallbackNormal: ObjVec3,
        mesh: ObjMeshData,
    ) {
        val position = positions[ref.position]
        val texcoord = ref.texcoord?.let(texcoords::getOrNull) ?: ObjVec2(0.0f, 0.0f)
        val normal = ref.normal?.let(normals::getOrNull) ?: fallbackNormal
        mesh.addVertex(position, texcoord, normal)
    }

    private fun parseObjFaceRef(
        token: String,
        positionCount: Int,
        texcoordCount: Int,
        normalCount: Int,
    ): ObjFaceRef? {
        val parts = token.split('/')
        val position = objIndex(parts.getOrNull(0), positionCount) ?: return null
        val texcoord = objIndex(parts.getOrNull(1), texcoordCount)
        val normal = objIndex(parts.getOrNull(2), normalCount)
        return ObjFaceRef(position, texcoord, normal)
    }

    private fun objIndex(value: String?, size: Int): Int? {
        if (value.isNullOrEmpty()) return null
        val index = value.toIntOrNull() ?: return null
        val resolved = if (index > 0) index - 1 else size + index
        return resolved.takeIf { it >= 0 }
    }

    private fun triangleNormal(a: ObjVec3, b: ObjVec3, c: ObjVec3): ObjVec3 =
        normalize(
            ObjVec3(
                (b.y - a.y) * (c.z - a.z) - (b.z - a.z) * (c.y - a.y),
                (b.z - a.z) * (c.x - a.x) - (b.x - a.x) * (c.z - a.z),
                (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x),
            ),
        )

    private fun normalize(vector: ObjVec3): ObjVec3 {
        val length =
            kotlin.math.sqrt(
                (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).toDouble(),
            ).toFloat()
        if (length <= 0.000001f) return ObjVec3(0.0f, 1.0f, 0.0f)
        return ObjVec3(vector.x / length, vector.y / length, vector.z / length)
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
        val instanceId = call.int("instanceId")
        if (!instances.containsKey(instanceId)) return
        nativeEngine.playModelAnimation(
            instanceId,
            call.int("animationIndex"),
            call.boolean("loop", true),
            call.float("speed", 1.0f),
            System.nanoTime(),
        )
    }

    private fun pauseModelAnimation(id: Int) {
        if (!instances.containsKey(id)) return
        nativeEngine.pauseModelAnimation(id, System.nanoTime())
    }

    private fun resumeModelAnimation(id: Int) {
        if (!instances.containsKey(id)) return
        nativeEngine.resumeModelAnimation(id, System.nanoTime())
    }

    private fun stopModelAnimation(id: Int) {
        if (!instances.containsKey(id)) return
        nativeEngine.stopModelAnimation(id)
    }

    private fun createLight(call: MethodCall) {
        val id = call.int("id")
        destroyLight(id)
        nativeEngine.upsertLight(
            id,
            call.int("type"),
            call.float("r"),
            call.float("g"),
            call.float("b"),
            call.float("intensity"),
            call.float("x"),
            call.float("y"),
            call.float("z"),
            call.float("dx"),
            call.float("dy"),
            call.float("dz"),
            call.float("falloffRadius"),
            call.boolean("castShadows"),
        )
        val light = nativeEngine.light(id) ?: return
        val entity = EntityManager.get().create()
        val type =
            if (light[1].toInt() == 1) LightManager.Type.POINT else LightManager.Type.SUN
        val builder =
            LightManager.Builder(type)
                .color(light[2], light[3], light[4])
                .intensity(light[5])
                .castShadows(light[13] != 0.0f)
        if (type == LightManager.Type.POINT) {
            builder
                .position(light[6], light[7], light[8])
                .falloff(light[12])
        } else {
            builder.direction(light[9], light[10], light[11])
        }
        builder.build(modelViewer.engine, entity)
        lights[id] = entity
        modelViewer.scene.addEntity(entity)
    }

    private fun updateLight(
        call: MethodCall,
        updateNative: (Int) -> Unit,
    ) {
        val id = call.int("id")
        updateNative(id)
        applyLightState(id)
    }

    private fun applyLightState(id: Int) {
        val entity = lights[id] ?: return
        val light = nativeEngine.light(id) ?: return
        val manager = modelViewer.engine.lightManager
        val instance = manager.getInstance(entity)
        if (light[1].toInt() == 1) {
            manager.setPosition(instance, light[6], light[7], light[8])
        } else {
            manager.setDirection(instance, light[9], light[10], light[11])
        }
        manager.setIntensity(instance, light[5])
    }

    private fun destroyLight(id: Int) {
        nativeEngine.removeLight(id)
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

    private fun MethodCall.map(name: String): Map<*, *> =
        argument<Map<*, *>>(name) ?: emptyMap<Any, Any>()

    private fun Map<*, *>.int(name: String, fallback: Int): Int =
        (get(name) as? Number)?.toInt() ?: fallback

    private fun Map<*, *>.float(name: String, fallback: Float = 0.0f): Float =
        (get(name) as? Number)?.toFloat() ?: fallback

    private fun Map<*, *>.boolean(name: String, fallback: Boolean = false): Boolean =
        get(name) as? Boolean ?: fallback

    private fun Map<*, *>.string(name: String): String = get(name) as? String ?: ""

    private fun quality(value: String): View.QualityLevel =
        when (value.lowercase()) {
            "medium" -> View.QualityLevel.MEDIUM
            "high" -> View.QualityLevel.HIGH
            "ultra" -> View.QualityLevel.ULTRA
            else -> View.QualityLevel.LOW
        }

    private fun shadowType(value: String): View.ShadowType =
        when (value.lowercase()) {
            "vsm" -> View.ShadowType.VSM
            "dpcf" -> View.ShadowType.DPCF
            "pcss" -> View.ShadowType.PCSS
            else -> View.ShadowType.PCF
        }

    private data class NativeModelAsset(
        val asset: FilamentAsset,
    )

    private enum class NativeModelVerticalAnchor(val nativeValue: Int) {
        ORIGIN(0),
        CENTER(1),
        BOTTOM(2),
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
        val instance: FilamentInstance,
        val transform: FloatArray = FloatArray(16),
    )

    private data class NativeTexturedMesh(
        val asset: FilamentAsset,
        val customMaterial: NativeMeshMaterial?,
    )

    private data class ObjVec3(val x: Float, val y: Float, val z: Float)

    private data class ObjVec2(val u: Float, val v: Float)

    private data class ObjFaceRef(
        val position: Int,
        val texcoord: Int?,
        val normal: Int?,
    )

    private data class ObjPrimitiveBuffer(
        val mesh: ObjMeshData,
        val positionOffset: Int,
        val positionBytes: Int,
        val normalOffset: Int,
        val normalBytes: Int,
        val uvOffset: Int,
        val uvBytes: Int,
        val indexOffset: Int,
        val indexBytes: Int,
        val useShortIndices: Boolean,
    )

    private data class ObjMaterial(
        val name: String = "",
        val baseColor: FloatArray = floatArrayOf(1.0f, 1.0f, 1.0f, 1.0f),
        var roughness: Float = 0.85f,
    ) {
        fun toGltfJson(): String =
            """{"doubleSided":true,"pbrMetallicRoughness":{"baseColorFactor":[${baseColor[0]},${baseColor[1]},${baseColor[2]},${baseColor[3]}],"metallicFactor":0,"roughnessFactor":$roughness}}"""
    }

    private class ObjMeshData(val materialName: String) {
        val positions = mutableListOf<Float>()
        val normals = mutableListOf<Float>()
        val texcoords = mutableListOf<Float>()
        val indices = mutableListOf<Int>()
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var minZ = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        var maxZ = Float.NEGATIVE_INFINITY
        val vertexCount: Int
            get() = positions.size / 3

        fun addVertex(position: ObjVec3, texcoord: ObjVec2, normal: ObjVec3) {
            positions += position.x
            positions += position.y
            positions += position.z
            normals += normal.x
            normals += normal.y
            normals += normal.z
            texcoords += texcoord.u
            texcoords += texcoord.v
            indices += vertexCount - 1
            minX = minOf(minX, position.x)
            minY = minOf(minY, position.y)
            minZ = minOf(minZ, position.z)
            maxX = maxOf(maxX, position.x)
            maxY = maxOf(maxY, position.y)
            maxZ = maxOf(maxZ, position.z)
        }
    }

    private data class NativeMeshMaterial(
        val material: Material?,
        val materialInstance: MaterialInstance?,
        val textures: List<Texture>,
    )

    companion object {
        init {
            System.loadLibrary("filament-jni")
            System.loadLibrary("filament-utils-jni")
            System.loadLibrary("gltfio-jni")
        }
    }
}
