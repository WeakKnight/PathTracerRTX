import Scene.Shading;
import Scene.Raytracing;

#define M_1_PI  0.318309886183790671538
#define M_PI     3.14159265358979323846

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

	float beta = u.y * M_PI * 2.0;

	return float3(sinTheta * cos(beta), sinTheta * sin(beta), cosTheta);
}

float3 CosineWeightedRandomPointOnHemiSphere(float2 u)
{
    float F = u.x;
    float cosine2Theta = 1.0f  - 2.0f * F;
    float theta = 0.5f * acos(cosine2Theta);
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    
    float beta = u.y * M_PI * 2.0;
    
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

float ggxNormalDistribution( float NdotH, float roughness )
{
	float a2 = roughness * roughness;
	float d = max(((NdotH * a2 - NdotH) * NdotH + 1.0), 0.000001);
	return a2 / (d * d * M_PI);
}

// This from Schlick 1994, modified as per Karas in SIGGRAPH 2013 "Physically Based Shading" course
//
// This function can be used for "G" in the Cook-Torrance model:  D*G*F / (4*NdotL*NdotV)
float ggxSchlickMaskingTerm(float NdotL, float NdotV, float roughness)
{
	// Karis notes they use alpha / 2 (or roughness^2 / 2)
	float k = roughness*roughness / 2.0;

	// Karis also notes they can use the following equation, but only for analytical lights
	//float k = (roughness + 1)*(roughness + 1) / 8; 

	// Compute G(v) and G(l).  These equations directly from Schlick 1994
	//     (Though note, Schlick's notation is cryptic and confusing.)
	float g_v = NdotV / (NdotV*(1.0 - k) + k);
	float g_l = NdotL / (NdotL*(1.0 - k) + k);

	// Return G(v) * G(l)
	return g_v * g_l;
}

float3 schlickFresnel(float3 f0, float lDotH)
{
	return f0 + (float3(1.0f, 1.0f, 1.0f) - f0) * pow(1.0f - lDotH, 5.0f);
}

// When using this function to sample, the probability density is:
//      pdf = D * NdotH / (4 * HdotV)
float3 getGGXMicrofacet(inout uint randSeed, float roughness, float3 hitNorm)
{
	// Get our uniform random numbers
	float2 randVal = float2(rand_next(randSeed), rand_next(randSeed));

    float3 B = 0.0;
    float3 T = 0.0;

    BranchlessONB(hitNorm, B, T);

	// GGX NDF sampling
	float a2 = roughness * roughness;
	float cosThetaH = sqrt(max(0.0f, (1.0-randVal.x)/((a2-1.0)*randVal.x+1) ));
	float sinThetaH = sqrt(max(0.0f, 1.0f - cosThetaH * cosThetaH));
	float phiH = randVal.y * M_PI * 2.0f;

	// Get our GGX NDF sample (i.e., the half vector)
	return T * (sinThetaH * cos(phiH)) +
           B * (sinThetaH * sin(phiH)) +
           hitNorm * cosThetaH;
}

float probabilityToSampleDiffuse(float3 difColor, float3 specColor)
{
	float lumDiffuse = max(0.01f, luminance(difColor.rgb));
	float lumSpecular = max(0.01f, luminance(specColor.rgb));
	return lumDiffuse / (lumDiffuse + lumSpecular);
}

float2 wsVectorToLatLong(float3 dir)
{
    float3 p = normalize(dir);
    float u = (1.f + atan2(p.x, -p.z) * M_1_PI) * 0.5f;
    float v = acos(p.y) * M_1_PI;
    return float2(u, v);
}

float PowerHeuristic(int numf, float fPdf, int numg, float gPdf) 
{
	float f = numf * fPdf;
	float g = numg * gPdf;

	return (f * f) / (f * f + g * g);
}