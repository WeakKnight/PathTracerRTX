cbuffer PPCB: register(b0)
{
    float exposure;
}

Texture2D<float4> _texLinearResult: register( t0 );
SamplerState _linearSampler : register( s0 );

float3 ACESFilmic(float3 x)
{
    x = x * 0.6;
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}

float3 LinearToSrgbBranchless(half3 lin)
{
 lin = max(6.10352e-5, lin); // minimum positive non-denormal (fixes black problem on DX11 AMD and NV)
 return min(lin * 12.92, pow(max(lin, 0.00313067), 1.0 / 2.4) * 1.055 - 0.055);
 // Possible that mobile GPUs might have native pow() function?
 //return min(lin * 12.92, exp2(log2(max(lin, 0.00313067)) * (1.0/2.4) + log2(1.055)) - 0.055);
}

float4 main(in float2 UV : TEXCOORD) : SV_TARGET
{
    float3 lin = exposure * _texLinearResult.Sample( _linearSampler, UV).rgb;
    float3 toneColor = ACESFilmic(lin);
    // float3 result = LinearToSrgbBranchless(toneColor);
    return float4(toneColor, 1.0);
}
