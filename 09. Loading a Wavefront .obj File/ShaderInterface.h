#ifndef SHADER_INTERFACE_H
#define SHADER_INTERFACE_H

// This header is shared between our C++ code and
// our Metal shaders, so we have a common interface
// for sending data from the CPU to the GPU

enum VertexAttributeIndex {
    VertexAttributeIndex_Position = 0,
    VertexAttributeIndex_Color,
    VertexAttributeIndex_TexCoords,
    VertexAttributeIndex_Normal,
    VertexAttributeIndex_Count
};

enum VertexBufferIndex  {
    VertexBufferIndex_Attributes = 0,
    VertexBufferIndex_Uniforms = 1,
    BufferIndexCount
};

#endif
