#include <metal_stdlib>

using namespace metal;

#include "ShaderInterface.h"

struct VertexInput {
    float2 position [[attribute(VertexAttributeIndex_Position)]];
};

struct ShaderInOut {
    float4 position [[position]];
    float4 color;
};

vertex ShaderInOut vert(VertexInput in [[stage_in]],
                        constant Uniforms& uniforms [[buffer(VertexBufferIndex_Uniforms)]]) 
{
    ShaderInOut out;
    out.position = float4(in.position + uniforms.pos, 0.0, 1.0);
    out.color = uniforms.color;
    return out;
}

fragment float4 frag(ShaderInOut in [[stage_in]]) 
{
    return in.color;
}
