#pragma once
#include "HaltonSampler.h"

inline float Halton(int index, int base)
{
    float r = 0;
    float f = 1.0f / (float)base;
    for (int i = index; i > 0; i /= base) {
        r += f * (i % base);
        f /= (float)base;
    }
    return r;
}

HaltonSampler::HaltonSampler()
{
    auto now = std::chrono::high_resolution_clock::now();
    auto msTime = std::chrono::time_point_cast<std::chrono::milliseconds>(now);
    m_Rng = std::mt19937(uint32_t(msTime.time_since_epoch().count()));

    m_randomOffset = float2(m_RngDist(m_Rng), m_RngDist(m_Rng));
}

float2 HaltonSampler::Sample()
{
    float2 samplerPos = float2(Halton(m_Index, m_XBase) - 0.5f, Halton(m_Index, m_YBase) - 0.5f);

    float finalX = samplerPos.x + m_randomOffset.x;
    if (finalX >= 0.5f)
    {
        finalX -= 1.0f;
    }

    float finalY = samplerPos.y + m_randomOffset.y;
    if (finalY >= 0.5f)
    {
        finalY -= 1.0f;
    }

    m_Index++;

    return float2(finalX, finalY);
}
