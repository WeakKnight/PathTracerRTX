#pragma once
#include <vector>

class CDF
{
public:
    CDF();

    void Init();

    // rand from 0 to tatal, return the correspond id
    int Sample() const;

    void Add(float val);

    float total;
    std::vector<float> cd;
};
