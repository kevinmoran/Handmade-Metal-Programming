#pragma once

struct float2
{
    float x, y;
};

union float4
{
    struct {
    float x, y, z, w;
    };
    struct {
        float r, g, b, a;
    };
};
