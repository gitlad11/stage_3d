material {
    name : "Water Waves",
    shadingModel : lit,
    doubleSided : true,
    blending : opaque,
    requires : [
        uv0
    ],
    parameters : [
        {
            type : sampler2d,
            name : albedo
        },
        {
            type : sampler2d,
            name : normalMap
        },
        {
            type : sampler2d,
            name : roughnessMap
        },
        {
            type : float4,
            name : tint
        },
        {
            type : float,
            name : roughness
        },
        {
            type : float,
            name : metallic
        },
        {
            type : float,
            name : reflectance
        },
        {
            type : float,
            name : windStrength
        },
        {
            type : float,
            name : windScale
        },
        {
            type : float,
            name : waveStrength
        },
        {
            type : float,
            name : waveScale
        },
        {
            type : float,
            name : waveSpeed
        },
        {
            type : float,
            name : flowSpeed
        },
        {
            type : float,
            name : sparkleStrength
        },
        {
            type : float,
            name : normalStrength
        },
        {
            type : float,
            name : roughnessMapStrength
        }
    ]
}

vertex {
    void materialVertex(inout MaterialVertexInputs material) {
        float time = getUserTime().x;
        float waveA = sin(
            (material.worldPosition.x * 1.7 + material.worldPosition.z * 0.9) *
            materialParams.waveScale + time * materialParams.waveSpeed * 6.28318
        );
        float waveB = cos(
            (material.worldPosition.z * 1.3 - material.worldPosition.x * 0.4) *
            materialParams.waveScale + time * materialParams.waveSpeed * 4.1
        );
        material.worldPosition.y += (waveA + waveB) * 0.5 * materialParams.waveStrength;
    }
}

fragment {
    void material(inout MaterialInputs material) {
        prepareMaterial(material);

        float time = getUserTime().x;
        vec2 uv = getUV0();
        vec2 flowA = vec2(time * materialParams.flowSpeed, time * materialParams.flowSpeed * 0.37);
        vec2 flowB = vec2(-time * materialParams.flowSpeed * 0.42, time * materialParams.flowSpeed * 0.25);

        vec4 baseA = texture(materialParams_albedo, uv + flowA);
        vec4 baseB = texture(materialParams_albedo, uv * 1.37 + flowB);
        vec3 normalA = texture(materialParams_normalMap, uv + flowA * 1.7).xyz * 2.0 - 1.0;
        vec3 normalB = texture(materialParams_normalMap, uv * 1.61 + flowB * 1.3).xyz * 2.0 - 1.0;
        vec3 waterNormal = normalize(mix(normalA, normalB, 0.45));
        waterNormal.xy *= materialParams.normalStrength;

        float roughnessSampleA = texture(materialParams_roughnessMap, uv + flowB).r;
        float roughnessSampleB = texture(materialParams_roughnessMap, uv * 1.23 + flowA).r;
        float roughnessSample = mix(roughnessSampleA, roughnessSampleB, 0.5);
        vec3 atlasColor = mix(baseA.rgb, baseB.rgb, 0.35);
        vec3 waterColor = mix(atlasColor, materialParams.tint.rgb, 0.48);
        waterColor += materialParams.tint.rgb * 0.08;

        float sparkleA = pow(max(baseA.r, max(baseA.g, baseA.b)), 5.0);
        float sparkleB = pow(max(baseB.r, max(baseB.g, baseB.b)), 6.0);
        float sparkle = (sparkleA * 0.6 + sparkleB * 0.4) * materialParams.sparkleStrength;

        material.baseColor = vec4(waterColor + sparkle, 1.0);
        material.normal = normalize(waterNormal);
        material.roughness = clamp(
            mix(materialParams.roughness, materialParams.roughness * max(roughnessSample, 0.35), materialParams.roughnessMapStrength),
            0.02,
            1.0
        );
        material.metallic = materialParams.metallic;
        material.reflectance = materialParams.reflectance;
    }
}
