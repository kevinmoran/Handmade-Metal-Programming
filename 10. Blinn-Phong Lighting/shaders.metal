
#include <metal_stdlib>

using namespace metal;

#include "ShaderInterface.h"

struct VertexInput {
    float3 position [[attribute(VertexAttributeIndex_Position)]];
    float2 uv [[attribute(VertexAttributeIndex_TexCoords)]];
    float3 normal [[attribute(VertexAttributeIndex_Normal)]];
};

struct ShaderInOut {
    float4 position [[position]];
    float3 posEye;
    float3 normalEye;
    float2 uv;
};

vertex ShaderInOut blinnPhongVert(VertexInput in [[stage_in]],
                                  constant VSUniforms& uniforms [[buffer(ShaderBufferIndex_Uniforms)]]) 
{
    ShaderInOut out;
    out.position = uniforms.modelViewProj * float4(in.position, 1.0);
    out.posEye = (uniforms.modelView * float4(in.position, 1.0)).xyz;
    out.normalEye = uniforms.normalMatrix * in.normal;
    out.uv = in.uv;
    return out;
}

fragment float4 blinnPhongFrag(ShaderInOut in [[stage_in]],
                               constant FSUniforms& uniforms [[buffer(ShaderBufferIndex_Uniforms)]],
                               texture2d<float> colorTexture [[texture(0)]],
                               sampler sam [[sampler(0)]]) 
{
    float3 diffuseColor = colorTexture.sample(sam, in.uv).xyz;

    float3 fragToCamDir = normalize(-in.posEye);
    
    // Directional Light
    float3 dirLightIntensity;
    {
        float ambientStrength = 0.1;
        float specularStrength = 0.9;
        float specularExponent = 100;
        float3 lightDirEye = uniforms.dirLight.dirEye.xyz;
        float3 lightColor = uniforms.dirLight.color.xyz;

        float3 iAmbient = float3(ambientStrength);

        float diffuseFactor = max(0.0, dot(in.normalEye, lightDirEye));
        float3 iDiffuse = diffuseFactor;

        float3 halfwayEye = normalize(fragToCamDir + lightDirEye);
        float specularFactor = max(0.0, dot(halfwayEye, in.normalEye));
        float3 iSpecular = specularStrength * pow(specularFactor, 2*specularExponent);

        dirLightIntensity = (iAmbient + iDiffuse + iSpecular) * lightColor;
    }
    // Point Light
    float3 pointLightIntensity(0,0,0);
    for(int i=0; i<2; ++i)
    {
        float ambientStrength = 0.1;
        float specularStrength = 0.9;
        float specularExponent = 100;
        float3 lightDirEye = uniforms.pointLights[i].posEye.xyz - in.posEye;
        float inverseDistance = 1 / length(lightDirEye);
        lightDirEye *= inverseDistance; //normalise
        float3 lightColor = uniforms.pointLights[i].color.xyz;

        float3 iAmbient = float3(ambientStrength);

        float diffuseFactor = max(0.0, dot(in.normalEye, lightDirEye));
        float3 iDiffuse = diffuseFactor;

        float3 halfwayEye = normalize(fragToCamDir + lightDirEye);
        float specularFactor = max(0.0, dot(halfwayEye, in.normalEye));
        float3 iSpecular = specularStrength * pow(specularFactor, 2*specularExponent);

        pointLightIntensity += (iAmbient + iDiffuse + iSpecular) * lightColor * inverseDistance;
    }

    float3 result = (dirLightIntensity + pointLightIntensity) * diffuseColor;

    return float4(result, 1.0);
}

vertex float4 mvpVert(float3 position[[attribute(VertexAttributeIndex_Position)]] [[stage_in]],
                      constant VSUniforms& uniforms [[buffer(ShaderBufferIndex_Uniforms)]]) 
{
    return uniforms.modelViewProj * float4(position, 1.0);
}

fragment float4 uniformColorFrag(constant float4& color [[buffer(ShaderBufferIndex_Uniforms)]])
{
    return color;
}