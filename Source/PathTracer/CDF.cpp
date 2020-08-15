#include "CDF.h"
#include <assert.h>

CDF::CDF()
    :total(0.0f)
{
    Init();
}

void CDF::Init()
{
    cd = std::vector<float>({ 0.0f });
    total = (+0.0f);
}

// rand from 0 to tatal, return the correspond id
int CDF::Sample() const
{
    if (cd.size() == 1)
    {
        return 0;
    }

    float random = (static_cast <float> (rand()) / static_cast <float> (RAND_MAX)) * total;
    for (int i = 1; i < cd.size(); i++)
    {
        if (random <= cd[i] && random >= cd[i - (size_t)1])
        {
            return i - 1;
        }
    }

    assert(false);
    return 0;
}

void CDF::Add(float val)
{
    total += val;
    cd.push_back(total);
}
