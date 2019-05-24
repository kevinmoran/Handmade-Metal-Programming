#include "ShaderInterface.h"

#include <metal_stdlib>

using namespace metal;

struct VertexInput {
    float3 position [[attribute(VertexAttributeIndex_Position)]];
};

struct ShaderInOut {
    float4 position [[position]];
    float4 posModel;
};

vertex ShaderInOut vert(VertexInput in [[stage_in]],
                        constant float4x4& modelViewProj [[buffer(VertexBufferIndex_Uniforms)]]) 
{
    ShaderInOut out;
    out.position = modelViewProj * float4(in.position, 1.0);
    out.posModel = float4(in.position, 1.0);
    return out;
}

fragment float4 frag(ShaderInOut in [[stage_in]]) 
{
    return float4(abs(in.posModel.xyz), 1.0);
}
