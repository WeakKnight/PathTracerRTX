import Scene.Shading;
import Scene.Raytracing;

cbuffer RayGenCB {
	float gAORadius, gMinT;
	uint  gFrameCount;
}

Texture2D<float4> gPos, gNorm;
RWTexture2D<float4> gOutput;

struct AORayPayload {
  float aoVal;  // Stores 0 on a ray hit, 1 on ray miss
};

void BranchlessONB(inout float3 n, inout float3 b1, inout float3 b2)
{
	float s = sign(n.z);
	float a = -1.0f / (s + n.z);
  float b = n.x * n.y * a;
	b1 = float3(1.0f + s * n.x * n.x * a, s * b, -s * n.x);
	b2 = float3(b, s + n.y * n.y * a, -n.y);
}

float3 UniformRandomPointOnHemiSphere(float2 u)
{
	float cosTheta = u.x;
	float sinTheta = sqrt(1.0f - (cosTheta * cosTheta));
	if (sinTheta < 0.0f)
	{
		sinTheta = 0.0f;
	}

	float beta = u.y * 3.14159265 * 2.0;

	return float3(sinTheta * cos(beta), sinTheta * sin(beta), cosTheta);
}

float3 CosineWeightedRandomPointOnHemiSphere(float2 u)
{
    float F = u.x;
    float cosine2Theta = 1.0f  - 2.0f * F;
    float theta = 0.5f * acos(cosine2Theta);
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    
    float beta = u.y * 3.14159265 * 2.0;
    
    // z = 1 * cosTheta, r = 1 * sinTheta, x = cosBeta * sinTheta, y = sinBeta * sinTheta
    return float3(sinTheta * cos(beta), sinTheta * sin(beta), cosTheta);
}

float3 getCosHemisphereSample(uint randSeed, float3 N)
{
    float3 b1 = 0.0;
    float3 b2 = 0.0;

    BranchlessONB(N, b1, b2);

    float2 u = float2(rand_next(randSeed), rand_next(randSeed));
    float3 dir = CosineWeightedRandomPointOnHemiSphere(u);

    return N * dir.z + b1 * dir.x + b2 * dir.y;
}

float shootAmbientOcclusionRay( float3 orig, float3 dir, 
                                float minT,  float maxT )
{
  // Setup AO payload.  By default, assume our AO ray will *hit* (value = 0)
  AORayPayload  rayPayload = { 0.0f };  

  // Describe the ray we're shooting
  RayDesc       rayAO = { orig, minT, dir, maxT };

  // We're going to tell our ray to never run the closest-hit shader and to
  //     stop as soon as we find *any* intersection
  uint rayFlags = RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH |
                  RAY_FLAG_SKIP_CLOSEST_HIT_SHADER;

  // Trace our ray. 
  TraceRay(gRtScene, rayFlags, 0xFF, 0, 1, 0, rayAO, rayPayload );

  // Return our AO value out of the ray payload.
  return rayPayload.aoVal;
}

[shader("raygeneration")]
void AoRayGen()
{
  // Where is this thread's ray on screen?
  uint3 pixIdx = DispatchRaysIndex();
  uint3 numPix = DispatchRaysDimensions();

  uint randSeed = rand_init(pixIdx.x + pixIdx.y * numPix.x, gFrameCount, 16);

  // Load the position and normal from our g-buffer
  float4 worldPos  = gPos[pixIdx.xy];
  float3 worldNorm = gNorm[pixIdx.xy].xyz;

  // Default ambient occlusion value if we hit the background
  float aoVal = 1.0f;

  // worldPos.w == 0 for background pixels; only shoot AO rays elsewhere
  if (worldPos.w != 0.0f)
  {
    // Random ray, sampled on cosine-weighted hemisphere around normal 
    float3 worldDir = getCosHemisphereSample(randSeed, worldNorm);

    // Shoot our ambient occlusion ray and update the final AO value
    aoVal = shootAmbientOcclusionRay(worldPos.xyz, worldDir, gMinT, gAORadius);
  }

  gOutput[pixIdx.xy] = float4(aoVal, aoVal, aoVal, 1.0f);
}

[shader("miss")]
void AoMiss(inout AORayPayload rayData)
{
	rayData.aoVal = 1.0f;
}

[shader("anyhit")]
void AoAnyHit(uniform HitShaderParams hitParams, inout AORayPayload rayData, BuiltInTriangleIntersectionAttributes attribs)
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
void AoClosestHit(inout AORayPayload, BuiltInTriangleIntersectionAttributes)
{
}
