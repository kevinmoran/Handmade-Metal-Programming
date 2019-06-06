#include "3DMaths.h"

float degreesToRadians(float degs)
{
	return degs * (M_PI / 180.0f);
}

float length(float3 v)
{
    float result = v.x*v.x + v.y*v.y + v.z*v.z;
    return result;
}

float length(float4 v)
{
    float result = v.x*v.x + v.y*v.y + v.z*v.z + v.w*v.w;
    return result;
}

float3 normalise(float3 v)
{
    float invLength = 1.f / length(v);
    float3 result = v * invLength;
    return result;
}

float4 normalise(float4 v)
{
    float invLength = 1.f / length(v);
    float4 result = v * invLength;
    return result;
}

float3 cross(float3 a, float3 b)
{
	float3 result;
	result.x = ((a.y * b.z) - (a.z * b.y));
	result.y = ((a.z * b.x) - (a.x * b.z));
	result.z = ((a.x * b.y) - (a.y * b.x));
	return result;
}

float3 operator* (float3 v, float f)
{
    float3 result = {v.x*f, v.y*f, v.z*f};
    return result;
}

float4 operator* (float4 v, float f)
{
    float4 result = {v.x*f, v.y*f, v.z*f, v.w*f};
    return result;
}

float3 operator+= (float3 &lhs, float3 rhs) {
	lhs.x += rhs.x;
	lhs.y += rhs.y;
	lhs.z += rhs.z;
	return lhs;
}

float3 operator-= (float3 &lhs, float3 rhs) {
	lhs.x -= rhs.x;
	lhs.y -= rhs.y;
	lhs.z -= rhs.z;
	return lhs;
}

float3 operator- (float3 v)
{
    float3 result = {-v.x, -v.y, -v.z};
    return result;
}

float4x4 scaleMat(float s)
{
	return (float4x4) {
		s, 0, 0, 0,
		0, s, 0, 0,
		0, 0, s, 0,
		0, 0, 0, 1
	};
}

float4x4 rotateXMat(float rad) {
	float4x4 result = {};
	float sinTheta = sinf(rad);
	float cosTheta = cosf(rad);
    result.m[0][0] = 1.f;
	result.m[1][1] = cosTheta;
	result.m[1][2] = sinTheta;
	result.m[2][1] = -sinTheta;
	result.m[2][2] = cosTheta;
    result.m[3][3] = 1.f;
	return result;
}

float4x4 rotateYMat(float rad) {
	float4x4 result = {};
	float sinTheta = sinf(rad);
	float cosTheta = cosf(rad);
	result.m[0][0] = cosTheta;
	result.m[0][2] = -sinTheta;
    result.m[1][1] = 1.f;
	result.m[2][0] = sinTheta;
	result.m[2][2] = cosTheta;
    result.m[3][3] = 1.f;
	return result;
}

float4x4 translationMat(float3 trans)
{
    float4x4 result = {};
    result.m[0][0] = 1.f;
    result.m[1][1] = 1.f;
    result.m[2][2] = 1.f;
    result.m[3][0] = trans.x;
    result.m[3][1] = trans.y;
    result.m[3][2] = trans.z;
    result.m[3][3] = 1.f;
    return result;
}

float4x4 makePerspectiveMat(float aspectRatio, float fovY, float zNear, float zFar)
{
    // float yScale = 1 / tanf(0.5f * fovY); 
    // NOTE: 1/tan(X) = tan(90degs - X), so we can avoid a divide
    // float yScale = tanf((0.5f * M_PI) - (0.5f * fovY));
    float yScale = tanf(0.5f * (M_PI - fovY));
    float xScale = yScale / aspectRatio;
    float zRangeInverse = 1.f / (zNear - zFar);
    float zScale = zFar * zRangeInverse;
    float zTranslation = zFar * zNear * zRangeInverse;

    float4x4 result = (float4x4){
        xScale, 0, 0, 0,
        0, yScale, 0, 0,
        0, 0, zScale, -1,
        0, 0, zTranslation, 0 
    };
    return result;
}

float4x4 operator* (float4x4 a, float4x4 b)
{
    float4x4 result = {};
	for(int col = 0; col < 4; ++col) {
		for(int row = 0; row < 4; ++row) {
			float sum = 0.0f;
			for(int i = 0; i < 4; ++i) {
				sum += b.m[col][i] * a.m[i][row];
			}
			result.m[col][row] = sum;
		}
	}
	return result;
}

float4 operator* (float4x4 m, float4 v)
{
	float x =
		m.m[0][0] * v.x +
		m.m[1][0] * v.y +
		m.m[2][0] * v.z +
		m.m[3][0] * v.w;
	float y = 
		m.m[0][1] * v.x +
		m.m[1][1] * v.y +
		m.m[2][1] * v.z +
		m.m[3][1] * v.w;
	float z = 
		m.m[0][2] * v.x +
		m.m[1][2] * v.y +
		m.m[2][2] * v.z +
		m.m[3][2] * v.w;
	float w = 
		m.m[0][3] * v.x +
		m.m[1][3] * v.y +
		m.m[2][3] * v.z +
		m.m[3][3] * v.w;
	float4 result = {x, y, z, w};
	return result;
}

float4x4 transpose(float4x4 m)
{
	return float4x4 {
		m.m[0][0], m.m[1][0], m.m[2][0], m.m[3][0], 
		m.m[0][1], m.m[1][1], m.m[2][1], m.m[3][1], 
		m.m[0][2], m.m[1][2], m.m[2][2], m.m[3][2], 
		m.m[0][3], m.m[1][3], m.m[2][3], m.m[3][3]
	};
}

float3x3 float4x4ToFloat3x3(float4x4 m)
{
	float3x3 result = {
		m.m[0][0], m.m[0][1], m.m[0][2], 0.0, 
		m.m[1][0], m.m[1][1], m.m[1][2], 0.0,
		m.m[2][0], m.m[2][1], m.m[2][2], 0.0
	};
	return result;
}
