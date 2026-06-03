material {
    name : "Grass Wind",
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
            name : windStrength
        },
        {
            type : float,
            name : windScale
        }
    ]
}

vertex {
    void materialVertex(inout MaterialVertexInputs material) {
        float bladeMask = material.uv0.y;
        float wind = sin(
            (material.worldPosition.x + material.worldPosition.z) *
            materialParams.windScale + getUserTime().x * 6.28318
        );
        material.worldPosition.x += wind * materialParams.windStrength * bladeMask;
    }
}

fragment {
    void material(inout MaterialInputs material) {
        prepareMaterial(material);
        vec4 base = texture(materialParams_albedo, getUV0()) * materialParams.tint;
        material.baseColor = base;
        material.roughness = materialParams.roughness;
        material.metallic = materialParams.metallic;
    }
}
