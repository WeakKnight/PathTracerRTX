#pragma once
#include "Falcor.h"

using namespace Falcor;

class HaltonSampler
{
public:
    HaltonSampler();
    // from -0.5 to 0.5
    float2 Sample();
private:

    std::uniform_real_distribution<float> m_RngDist;
    std::mt19937                          m_Rng;

    float2 m_randomOffset;
    int m_Index = 0;
    int m_XBase = 2;
    int m_YBase = 3;
};
