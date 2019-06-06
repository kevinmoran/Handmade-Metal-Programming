#ifndef SHADER_INTERFACE_H
#define SHADER_INTERFACE_H

// This header is shared between our C++ code and
// our Metal shaders, so we have a common interface
// for sending data from the CPU to the GPU

enum VertexAttributeIndex {
    VertexAttributeIndex_Position = 0,
    VertexAttributeIndex_TexCoords,
    VertexAttributeIndex_Normal,
    VertexAttributeIndex_Count
};

enum ShaderBufferIndex  {
    ShaderBufferIndex_Attributes = 0,
    ShaderBufferIndex_Uniforms,
    BufferIndexCount
};

struct VSUniforms
{
    float4x4 modelView;
    float4x4 modelViewProj;
    float3x3 normalMatrix;
};

struct DirectionalLight
{
    float4 dirEye; //NOTE: Direction towards the light
    float4 color;
};

struct PointLight
{
    float4 posEye;
    float4 color;
};

struct FSUniforms
{
    DirectionalLight dirLight;
    PointLight pointLights[2];
};

#endif
