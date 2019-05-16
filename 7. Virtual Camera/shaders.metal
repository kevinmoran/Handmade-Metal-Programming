#include <metal_stdlib>

using namespace metal;

#include "ShaderInterface.h"

struct VertexInput {
    float2 position [[attribute(VertexAttributeIndex_Position)]];
    float2 uv [[attribute(VertexAttributeIndex_TexCoords)]];
};

struct ShaderInOut {
    float4 position [[position]];
    float2 uv;
};

vertex ShaderInOut vert(VertexInput in [[stage_in]],
                        constant float4x4& modelViewProj [[buffer(VertexBufferIndex_Uniforms)]]) 
{
    ShaderInOut out;
    out.position = modelViewProj * float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 frag(ShaderInOut in [[stage_in]],
                     texture2d<float> colorTexture [[texture(0)]],
                     sampler sam [[sampler(0)]]) 
{
    return colorTexture.sample(sam, in.uv);
}
