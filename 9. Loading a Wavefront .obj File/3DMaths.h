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

struct float4x4
{
    // Stored in column major, access with [col][row]
    float m[4][4];
};

float degreesToRadians(float degs);

float length(float3 v);
float3 normalise(float3 v);
float3 cross(float3 a, float3 b); 
float3 operator* (float3 v, float f);
float3 operator+= (float3 &lhs, float3 rhs);
float3 operator-= (float3 &lhs, float3 rhs);
float3 operator- (float3 v);

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
