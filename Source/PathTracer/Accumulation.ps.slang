cbuffer AccumCB: register(b0)
{
    uint AccumFrameIndex;
}

Texture2D<float4> _LinearResult: register( t0 );
Texture2D<float4> _AccumHistory: register( t1 );

SamplerState _pointSampler : register( s1 );

float4 main(in float2 UV : TEXCOORD) : SV_TARGET
{
    float3 currentResult = _LinearResult.Sample( _pointSampler, UV).rgb;
    float3 accumulatedResult = _AccumHistory.Sample( _pointSampler, UV).rgb;
    float3 result = currentResult * (1.0 / AccumFrameIndex) + accumulatedResult * ((AccumFrameIndex - 1.0)/AccumFrameIndex);

    return float4(result, 1.0);
}
