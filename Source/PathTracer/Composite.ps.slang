import Scene.Shading;
import Scene.Raster;

cbuffer CompositeCB: register(b0)
{
    int enableDebug;
    int debugType;
}

Texture2D<float4> _GBufferAlbedo: register( t0 );
Texture2D<float4> _GBufferSpec: register( t1 );
Texture2D<float4> _GBufferPosition: register( t2 );
Texture2D<float4> _GBufferNormal: register( t3 );
Texture2D<float4> _GBufferExtra: register( t4 );
Texture2D<float4> _RayTraceResult: register( t5 );

SamplerState _linearSampler : register( s0 );
SamplerState _pointSampler : register( s1 );

float4 main(in float2 UV : TEXCOORD) : SV_TARGET
{
    if(enableDebug)
    {
        if(debugType == 0)
        {
            float3 albedo = _GBufferAlbedo.Sample( _pointSampler, UV).rgb;
            return float4(albedo, 1.0);
        }
        else if(debugType == 1)
        {
            float3 spec = _GBufferSpec.Sample( _pointSampler, UV).rgb;
            return float4(spec, 1.0);
        }
        else if(debugType == 2)
        {
            float3 pos = _GBufferPosition.Sample( _pointSampler, UV).rgb;
            return float4(pos, 1.0);
        }
        else if(debugType == 3)
        {
            float3 normal = _GBufferNormal.Sample( _pointSampler, UV).rgb;
            return float4(normal, 1.0);
        }
        else if(debugType == 4)
        {
            float3 raytracedColor = _RayTraceResult.Sample( _pointSampler, UV).rgb;
            return float4(raytracedColor, 1.0);
        }
    }
    else
    {
        float3 col = _RayTraceResult.Sample( _pointSampler, UV).rgb;
        float3 lin = (col);

        return float4(lin, 1.0);
    }
}
