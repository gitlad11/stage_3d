package com.example.jolt_physics_dart

internal class NativeStageEngine : AutoCloseable {
    private var handle = nativeCreate()

    fun resetCamera() = nativeResetCamera(handle)

    fun setCamera(
        targetX: Float,
        targetY: Float,
        targetZ: Float,
        yaw: Float,
        pitch: Float,
        distance: Float,
    ) = nativeSetCamera(handle, targetX, targetY, targetZ, yaw, pitch, distance)

    fun orbitCamera(deltaYaw: Float, deltaPitch: Float) =
        nativeOrbitCamera(handle, deltaYaw, deltaPitch)

    fun moveCamera(deltaX: Float, deltaY: Float) = nativeMoveCamera(handle, deltaX, deltaY)

    fun camera(): FloatArray = nativeGetCamera(handle)

    fun setEnvironment(
        skyR: Float,
        skyG: Float,
        skyB: Float,
        skyA: Float,
        ambientIntensity: Float,
        reflectionIntensity: Float,
    ) = nativeSetEnvironment(
        handle,
        skyR,
        skyG,
        skyB,
        skyA,
        ambientIntensity,
        reflectionIntensity,
    )

    fun environment(): FloatArray = nativeGetEnvironment(handle)

    fun upsertLight(
        id: Int,
        type: Int,
        r: Float,
        g: Float,
        b: Float,
        intensity: Float,
        x: Float,
        y: Float,
        z: Float,
        dx: Float,
        dy: Float,
        dz: Float,
        falloffRadius: Float,
        castShadows: Boolean,
    ) = nativeUpsertLight(
        handle,
        id,
        type,
        r,
        g,
        b,
        intensity,
        x,
        y,
        z,
        dx,
        dy,
        dz,
        falloffRadius,
        castShadows,
    )

    fun setLightPosition(id: Int, x: Float, y: Float, z: Float) =
        nativeSetLightPosition(handle, id, x, y, z)

    fun setLightDirection(id: Int, x: Float, y: Float, z: Float) =
        nativeSetLightDirection(handle, id, x, y, z)

    fun setLightIntensity(id: Int, intensity: Float) =
        nativeSetLightIntensity(handle, id, intensity)

    fun light(id: Int): FloatArray? = nativeGetLight(handle, id)

    fun removeLight(id: Int) = nativeRemoveLight(handle, id)

    fun registerModelAsset(
        assetId: Int,
        normalizedScale: Float,
        verticalAnchor: Int,
        center: FloatArray,
        halfExtent: FloatArray,
    ) = nativeRegisterModelAsset(
        handle,
        assetId,
        normalizedScale,
        verticalAnchor,
        center[0],
        center[1],
        center[2],
        halfExtent[0],
        halfExtent[1],
        halfExtent[2],
    )

    fun createModelInstance(instanceId: Int, assetId: Int): Boolean =
        nativeCreateModelInstance(handle, instanceId, assetId)

    fun setModelTransform(
        instanceId: Int,
        x: Float,
        y: Float,
        z: Float,
        qx: Float,
        qy: Float,
        qz: Float,
        qw: Float,
    ) = nativeSetModelTransform(handle, instanceId, x, y, z, qx, qy, qz, qw)

    fun fillModelMatrix(instanceId: Int, target: FloatArray) =
        nativeFillModelMatrix(handle, instanceId, target)

    fun removeModelInstance(instanceId: Int) = nativeRemoveModelInstance(handle, instanceId)

    fun removeModelAsset(assetId: Int): Boolean = nativeRemoveModelAsset(handle, assetId)

    fun playModelAnimation(
        instanceId: Int,
        animationIndex: Int,
        loop: Boolean,
        speed: Float,
        nowNanos: Long,
        paused: Boolean = false,
    ) = nativePlayModelAnimation(
        handle,
        instanceId,
        animationIndex,
        loop,
        speed,
        nowNanos,
        paused,
    )

    fun pauseModelAnimation(instanceId: Int, nowNanos: Long) =
        nativePauseModelAnimation(handle, instanceId, nowNanos)

    fun resumeModelAnimation(instanceId: Int, nowNanos: Long) =
        nativeResumeModelAnimation(handle, instanceId, nowNanos)

    fun stopModelAnimation(instanceId: Int) = nativeStopModelAnimation(handle, instanceId)

    fun modelAnimationIndex(instanceId: Int): Int =
        nativeGetModelAnimationIndex(handle, instanceId)

    fun sampleModelAnimationTime(
        instanceId: Int,
        frameTimeNanos: Long,
        durationSeconds: Float,
    ): Float =
        nativeSampleModelAnimationTime(handle, instanceId, frameTimeNanos, durationSeconds)

    override fun close() {
        if (handle == 0L) return
        nativeDestroy(handle)
        handle = 0L
    }

    companion object {
        init {
            System.loadLibrary("jolt_ffi")
        }

        @JvmStatic private external fun nativeCreate(): Long
        @JvmStatic private external fun nativeDestroy(handle: Long)
        @JvmStatic private external fun nativeResetCamera(handle: Long)
        @JvmStatic private external fun nativeSetCamera(
            handle: Long,
            targetX: Float,
            targetY: Float,
            targetZ: Float,
            yaw: Float,
            pitch: Float,
            distance: Float,
        )
        @JvmStatic private external fun nativeOrbitCamera(
            handle: Long,
            deltaYaw: Float,
            deltaPitch: Float,
        )
        @JvmStatic private external fun nativeMoveCamera(
            handle: Long,
            deltaX: Float,
            deltaY: Float,
        )
        @JvmStatic private external fun nativeGetCamera(handle: Long): FloatArray
        @JvmStatic private external fun nativeSetEnvironment(
            handle: Long,
            skyR: Float,
            skyG: Float,
            skyB: Float,
            skyA: Float,
            ambientIntensity: Float,
            reflectionIntensity: Float,
        )
        @JvmStatic private external fun nativeGetEnvironment(handle: Long): FloatArray
        @JvmStatic private external fun nativeUpsertLight(
            handle: Long,
            id: Int,
            type: Int,
            r: Float,
            g: Float,
            b: Float,
            intensity: Float,
            x: Float,
            y: Float,
            z: Float,
            dx: Float,
            dy: Float,
            dz: Float,
            falloffRadius: Float,
            castShadows: Boolean,
        )
        @JvmStatic private external fun nativeSetLightPosition(
            handle: Long,
            id: Int,
            x: Float,
            y: Float,
            z: Float,
        )
        @JvmStatic private external fun nativeSetLightDirection(
            handle: Long,
            id: Int,
            x: Float,
            y: Float,
            z: Float,
        )
        @JvmStatic private external fun nativeSetLightIntensity(
            handle: Long,
            id: Int,
            intensity: Float,
        )
        @JvmStatic private external fun nativeGetLight(handle: Long, id: Int): FloatArray?
        @JvmStatic private external fun nativeRemoveLight(handle: Long, id: Int)
        @JvmStatic private external fun nativeRegisterModelAsset(
            handle: Long,
            assetId: Int,
            normalizedScale: Float,
            verticalAnchor: Int,
            centerX: Float,
            centerY: Float,
            centerZ: Float,
            halfExtentX: Float,
            halfExtentY: Float,
            halfExtentZ: Float,
        )
        @JvmStatic private external fun nativeCreateModelInstance(
            handle: Long,
            instanceId: Int,
            assetId: Int,
        ): Boolean
        @JvmStatic private external fun nativeSetModelTransform(
            handle: Long,
            instanceId: Int,
            x: Float,
            y: Float,
            z: Float,
            qx: Float,
            qy: Float,
            qz: Float,
            qw: Float,
        )
        @JvmStatic private external fun nativeFillModelMatrix(
            handle: Long,
            instanceId: Int,
            target: FloatArray,
        )
        @JvmStatic private external fun nativeRemoveModelInstance(
            handle: Long,
            instanceId: Int,
        )
        @JvmStatic private external fun nativeRemoveModelAsset(
            handle: Long,
            assetId: Int,
        ): Boolean
        @JvmStatic private external fun nativePlayModelAnimation(
            handle: Long,
            instanceId: Int,
            animationIndex: Int,
            loop: Boolean,
            speed: Float,
            nowNanos: Long,
            paused: Boolean,
        )
        @JvmStatic private external fun nativePauseModelAnimation(
            handle: Long,
            instanceId: Int,
            nowNanos: Long,
        )
        @JvmStatic private external fun nativeResumeModelAnimation(
            handle: Long,
            instanceId: Int,
            nowNanos: Long,
        )
        @JvmStatic private external fun nativeStopModelAnimation(
            handle: Long,
            instanceId: Int,
        )
        @JvmStatic private external fun nativeGetModelAnimationIndex(
            handle: Long,
            instanceId: Int,
        ): Int
        @JvmStatic private external fun nativeSampleModelAnimationTime(
            handle: Long,
            instanceId: Int,
            frameTimeNanos: Long,
            durationSeconds: Float,
        ): Float
    }
}
