/***************************************************************************
 # Copyright (c) 2020, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
import Scene.Shading;
import Scene.Raytracing;
import RaytracingUtils;

#define M_1_PI  0.318309886183790671538
#define M_PI     3.14159265358979323846

cbuffer PerFrameCB
{
    float4x4 invView;
    float2 viewportDims;
    float tanHalfFovY;
    uint gFrameCount;
    float gMinT;
    uint gMaxDepth;
};

Texture2D<float4> gPos, gNorm, gAlbedo, gSpec, gEmissive;
Texture2D<float4> gEnvMap;

struct PrimaryRayData
{
    float4 color;
    uint depth;
    float hitT;
    uint randSeed;
};

struct ShadowRayData
{
    bool hit;
};

bool checkPointLightHit(uint lightIndex, float3 origin)
{
    float3 direction = gScene.lights[lightIndex].posW - origin;
    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = normalize(direction);
    ray.TMin = 0.001;
    ray.TMax = max(0.01, length(direction));

    ShadowRayData rayData;
    rayData.hit = true;
    TraceRay(gRtScene, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xFF, 1 /* ray index */, hitProgramCount, 1, ray, rayData);
    return rayData.hit;
}

bool checkDirectionalLightHit(float3 direction, float3 origin)
{
    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = normalize(direction);
    ray.TMin = 0.001;
    ray.TMax = max(0.01, length(direction));

    ShadowRayData rayData;
    rayData.hit = true;
    TraceRay(gRtScene, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xFF, 1 /* ray index */, hitProgramCount, 1, ray, rayData);
    return rayData.hit;
}

float3 shootIndirectRay(float3 orig, float3 dir, float minT, uint seed, uint depth)
{
    // Setup shadow ray
	RayDesc rayColor;
	rayColor.Origin = orig;  // Where does it start?
	rayColor.Direction = dir;  // What direction do we shoot it?
	rayColor.TMin = minT;         // The closest distance we'll count as a hit
	rayColor.TMax = 1.0e38f;      // The farthest distance we'll count as a hit

	PrimaryRayData hitData;
    hitData.randSeed = seed;
    hitData.depth = depth;

    TraceRay(gRtScene, 0 /*rayFlags*/, 0xFF, 0 /* ray index*/, hitProgramCount, 0, rayColor, hitData);
	return hitData.color.rgb;
}

float3 GGXDirectShading(uint randSeed, float3 posW, float3 N, float3 V, float3 albedo, float3 specular, float roughness)
{
    float3 result = 0.0;

    float NdotV = clamp(dot(N, V), 0.00001, 1.0);

    // Direct Lighting
    int lightCount = gScene.getLightCount();
    int i = min( int(lightCount * rand_next(randSeed)), lightCount - 1 );
    
    float3 radiance = 0.0;

    LightData light = gScene.getLight(i);
    float3 L = 0.0;
    float NdotL = 0.0;
    if (light.type == uint(LightType::Point))
    {
        if (!checkPointLightHit(i, posW))
        {
            float3 lightPosW = light.posW;
            L = normalize(lightPosW - posW);
            float distanceSquare = dot(lightPosW - posW, lightPosW - posW);
            float falloff = 1.0 / (distanceSquare + (0.01 * 0.01));
            NdotL = saturate(dot(N, L));
            radiance += light.intensity * falloff;
        }
        
    }
    else if(light.type == uint(LightType::Directional))
    {
        L = -normalize(light.dirW);
        if (!checkDirectionalLightHit(L, posW))
        {
            NdotL = saturate(dot(N, L));
            radiance += light.intensity;
        }
    }
    
    // Compute half vectors and additional dot products for GGX
    float3 H = normalize(V + L);
    float NdotH = saturate(dot(N, H));
    float LdotH = saturate(dot(L, H));
    
    // Evaluate terms for our GGX BRDF model
    float  D = ggxNormalDistribution(NdotH, clamp(roughness, 0.001, 0.999));
    float  G = ggxSchlickMaskingTerm(NdotL, NdotV, clamp(roughness, 0.001, 0.999));
    float3 F = schlickFresnel(specular, LdotH);

    // Evaluate the Cook-Torrance Microfacet BRDF model
    //     Cancel NdotL here to avoid catastrophic numerical precision issues.
    float3 ggxTerm = D*G*F / (4.0 * NdotV /* * NdotL */);

    result += lightCount * ggxTerm * radiance;
    result += lightCount * albedo * radiance * NdotL / M_PI;

    return result;
}

float3 GGXIndirectShading(uint randSeed, float3 posW, float3 N, float3 V, float3 albedo, float3 specular, float roughness, uint depth)
{
    float3 result = 0.0;
    float NdotV = clamp(dot(N, V), 0.000001, 1.0);

    // Importance Sampling Indirect Light, Split Into Specular Or Diffuse
    float probDiffuse = probabilityToSampleDiffuse(albedo, specular);
    float chooseDiffuse = (rand_next(randSeed) < probDiffuse);

    if(chooseDiffuse)
    {
        float3 bounceDir = getCosHemisphereSample(randSeed, N);
        float NdotLL = saturate(dot(N, bounceDir));

        float3 bounceColor = shootIndirectRay(posW, bounceDir, gMinT, randSeed, depth);
        float sampleProb = NdotLL / M_PI;
        result += (NdotLL * bounceColor * albedo.rgb / M_PI) / max(sampleProb, 0.00001) / probDiffuse;
    }
    else
    {
        // Randomly sample the NDF to get a microfacet in our BRDF 
        float3 H = getGGXMicrofacet(randSeed, roughness, N);
        // Compute outgoing direction based on this (perfectly reflective) facet
        float3 L = normalize(2.f * dot(V, H) * H - V);

        // Compute our color by tracing a ray in this direction
        float3 bounceColor = shootIndirectRay(posW, L, gMinT, randSeed, depth);

        // Compute some dot products needed for shading
        float  NdotL = clamp(dot(N, L), 0.000001, 1.0);
        float  NdotH = clamp(dot(N, H), 0.000001, 1.0);
        float  LdotH = clamp(dot(L, H), 0.000001, 1.0);

        // Evaluate our BRDF using a microfacet BRDF model
        float  D = ggxNormalDistribution(NdotH, roughness);          
        float  G = ggxSchlickMaskingTerm(NdotL, NdotV, roughness); 
        float3 F = schlickFresnel(specular, LdotH);                 
        float3 ggxTerm = D * G * F / (4.0 * NdotL * NdotV);        

        // What's the probability of sampling vector H from getGGXMicrofacet()?
        float  ggxProb = D * NdotH / (4.0 * LdotH);

        // Accumulate color:  ggx-BRDF * lightIn * NdotL / probability-of-sampling
        //    -> Note: Should really cancel and simplify the math above
        result += NdotL * bounceColor * ggxTerm / (ggxProb * (1.0f - probDiffuse));
    }

    return result;
}

[shader("miss")]
void ShadowMiss(inout ShadowRayData hitData)
{
    hitData.hit = false;
}

[shader("anyhit")]
void ShadowAnyHit(inout ShadowRayData hitData, in BuiltInTriangleIntersectionAttributes attribs)
{
    hitData.hit = true;
}

[shader("miss")]
void IndirectMiss(inout PrimaryRayData hitData)
{
    uint w = 0;
    uint h = 0;
    gEnvMap.GetDimensions(w, h);

    float2 uv = wsVectorToLatLong(WorldRayDirection()); 
    float3 backgroundColor = gEnvMap[uint2(uint(w * uv.x),uint(h * uv.y))].rgb;

    hitData.color = float4(backgroundColor, 1);
    hitData.hitT = -1;
}

[shader("anyhit")]
void IndirectAnyHit(
    uniform HitShaderParams                 hitParams,
    inout PrimaryRayData                    rayData,
    BuiltInTriangleIntersectionAttributes   attribs)
{
    // Alpha test for non-opaque geometry.
    VertexData v = getVertexData(hitParams, PrimitiveIndex(), attribs);
    uint materialID = gScene.getMaterialID(hitParams.getGlobalHitID());
    if (alphaTest(v, gScene.materials[materialID], gScene.materialResources[materialID], 0.f))
    {
        IgnoreHit();
    }
}

[shader("closesthit")]
void IndirectClosestHit(
    uniform HitShaderParams hitParams,
    inout PrimaryRayData hitData, in BuiltInTriangleIntersectionAttributes attribs)
{
    // Get the hit-point data
    float3 rayOrigW = WorldRayOrigin();
    float3 rayDirW = WorldRayDirection();
    float hitT = RayTCurrent();
    uint triangleIndex = PrimitiveIndex();

    // float3 posW = rayOrigW + hitT * rayDirW;

    // prepare the shading data
    VertexData v = getVertexData(hitParams, triangleIndex, attribs);
    uint materialID = gScene.getMaterialID(hitParams.getGlobalHitID());
    ShadingData sd = prepareShadingData(v, materialID, gScene.materials[materialID], gScene.materialResources[materialID], -rayDirW, 0);

    hitData.color.rgb = sd.emissive;
    
    hitData.color.rgb += GGXDirectShading(hitData.randSeed, sd.posW, sd.N, sd.V, sd.diffuse.rgb, sd.specular.rgb, sd.linearRoughness);
    
    if(hitData.depth < gMaxDepth)
    {
        hitData.color.rgb += GGXIndirectShading(hitData.randSeed, sd.posW, sd.N, sd.V, sd.diffuse.rgb, sd.specular.rgb, sd.linearRoughness, hitData.depth + 1);
    }

    hitData.hitT = hitT;
    hitData.color.a = 1;
}

[shader("raygeneration")]
void rayGen(
    uniform RWTexture2D<float4> gOutput)
{
    uint3 launchIndex = DispatchRaysIndex();
    
    float4 gPosVal  = gPos[launchIndex.xy];
    float3 posW     = gPosVal.xyz;
    float  hasColor = gPosVal.w;
	float3 N        = gNorm[launchIndex.xy].xyz;
    float4 albedo   = gAlbedo[launchIndex.xy];
    float4 specular = gSpec[launchIndex.xy];
    float3 emissive = gEmissive[launchIndex.xy].xyz;

    float3 result = 0.0;

    uint randSeed = rand_init(launchIndex.x + launchIndex.y * viewportDims.x, gFrameCount, 16);
    
    if(hasColor != 0)
    {
        result += emissive;
        float3 V = normalize(gScene.camera.getPosition());
        
        result += GGXDirectShading(randSeed, posW, N, V, albedo.rgb, specular.rgb, specular.a);
        result += GGXIndirectShading(randSeed, posW, N, V, albedo.rgb, specular.rgb, specular.a, 0);
    }
    else
    {
        RayDesc ray;
        ray = gScene.camera.computeRayPinhole(launchIndex.xy, viewportDims).toRayDesc();
        uint w = 0;
        uint h = 0;
        gEnvMap.GetDimensions(w, h);
        float2 uv = wsVectorToLatLong(ray.Direction); 
        result = gEnvMap[uint2(uint(w * uv.x),uint(h * uv.y))].rgb;
    }

    gOutput[launchIndex.xy] = float4(result, 1.0);
}
