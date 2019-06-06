#pragma once

#include <math.h>

struct float2
{
    float x, y;
};

struct float3
{
    float x, y, z;
};

union float4
{
    struct {
        float x, y, z, w;
    };
    struct {
        float3 xyz;
        float __IGNORE_w;
    };
};

struct float4x4
{
    // Stored in column major
    float m[4][4];
};

struct float3x3
{
    // Stored in column major
    // Metal aligns 3x3 matrices to 16 bytes so add an extra column.
    float m[3][4];
};

float degreesToRadians(float degs);

float length(float3 v);
float length(float4 v);
float3 normalise(float3 v);
float4 normalise(float4 v);
float3 cross(float3 a, float3 b); 
float3 operator* (float3 v, float f);
float4 operator* (float4 v, float f);
float3 operator+= (float3 &lhs, float3 rhs);
float3 operator-= (float3 &lhs, float3 rhs);
float3 operator- (float3 v);

float4x4 scaleMat(float s);
// Return matrix to rotate about x-axis by r radians
float4x4 rotateXMat(float r); 
// Return matrix to rotate about y-axis by r radians
float4x4 rotateYMat(float r);
// Return matrix to translate by vector t
float4x4 translationMat(float3 t);

// Transforms from view-space (x-right, y-up and negative-z-forward)
// to clip-space (x-right, y-up and z-forward)
// Assumes that in NDC, z goes from 0 to 1
float4x4 makePerspectiveMat(float aspectRatio, float fovY, float zNear, float zFar);

float4x4 operator* (float4x4 a, float4x4 b);
float4 operator* (float4x4 m, float4 v);
float4x4 transpose(float4x4 m);

float3x3 float4x4ToFloat3x3(float4x4 m);
