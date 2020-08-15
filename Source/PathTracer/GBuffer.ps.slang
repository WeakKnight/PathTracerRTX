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
import Scene.Raster;

struct GBuffer 
{
	float4 albedo    : SV_Target0;
    float4 spec      : SV_Target1;
    float4 positon   : SV_Target2;
    float4 normal    : SV_Target3;
    float4 extra     : SV_Target4;
    float4 emissive  : SV_Target5;
};

GBuffer main(VSOut vOut, uint triangleIndex : SV_PrimitiveID)
{
    float3 viewDir = normalize(gScene.camera.getPosition() - vOut.posW);
    ShadingData sd = prepareShadingData(vOut, triangleIndex, viewDir);

    // for (int i = 0; i < gScene.getLightCount(); i++)
    // {
    //     finalColor.rgb += evalMaterial(sd, gScene.getLight(i), 1).color.rgb;
    // }

    GBuffer gBufOut;
	gBufOut.albedo   = float4(sd.diffuse, sd.opacity);
    gBufOut.spec     = float4(sd.specular, sd.linearRoughness);
    gBufOut.positon  = float4(sd.posW, 1.f);
    gBufOut.normal   = float4(sd.N, length(sd.posW - gScene.camera.getPosition()));
    gBufOut.extra    = float4(sd.IoR, sd.doubleSided ? 1.f : 0.f, 0.f, 0.f);
    gBufOut.emissive = float4(sd.emissive, 1.f);
    return gBufOut;
}
