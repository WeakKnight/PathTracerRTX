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
#pragma once
#include "Falcor.h"
#include "HaltonSampler.h"

using namespace Falcor;

class PathTracer : public IRenderer
{
public:
    void onLoad(RenderContext* pRenderContext) override;
    void onFrameRender(RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo) override;
    void onShutdown() override;
    void onResizeSwapChain(uint32_t width, uint32_t height) override;
    bool onKeyEvent(const KeyboardEvent& keyEvent) override;
    bool onMouseEvent(const MouseEvent& mouseEvent) override;
    void onHotReload(HotReloadFlags reloaded) override;
    void onGuiRender(Gui* pGui) override;

private:
    void CreateGBufferFBO();
    void CreateGBufferPipeline();

    void CreateRTRenderTarget();
    void CreateRTPipeline();
    void RaytraceRender(RenderContext* pRenderContext);

    void CreateAccumFBO();
    void CreateAccumPipeline();

    void CreateCompositeFBO();
    void CreateCompositePipeline();

    void LoadScene();

private:
    HaltonSampler                   m_haltonSampler;

    /*
    GBuffer
    */
    Fbo::SharedPtr                  m_GBufferFbo;
    Texture::SharedPtr              m_GBufferAlbedoRT;/* albedo(rgb), opacity */
    Texture::SharedPtr              m_GBufferSpecRT;/* spcular(rgb), linear roughness */
    Texture::SharedPtr              m_GBufferPositionRT;/* position(rgb), packer */
    Texture::SharedPtr              m_GBufferNormalRT;/* normal(rgb), distance to camera */
    Texture::SharedPtr              m_GBufferExtraRT;/* ior, double sided, packer, packer */
    Texture::SharedPtr              m_GBufferEmissiveRT;/* Emissive RGB, packer */
    Texture::SharedPtr              m_GBufferDepthRT;

    GraphicsProgram::SharedPtr      m_GBufferProgram = nullptr;
    GraphicsVars::SharedPtr         m_GBufferProgramVars = nullptr;
    GraphicsState::SharedPtr        m_GBufferGraphicsState = nullptr;

    RasterizerState::SharedPtr      m_GBufferRasterizerState = nullptr;
    DepthStencilState::SharedPtr    m_GBufferDepthStencilState = nullptr;

    /*
    Ray Tracing
    */
    RtProgram::SharedPtr            m_RaytraceProgram = nullptr;
    RtProgramVars::SharedPtr        m_RtVars;
    Texture::SharedPtr              m_RaytraceRT;
    uint32_t                        m_MaxDepth = 0;
    uint32_t                        m_FrameCount = 0;     // Used for unique random seeds each frame

    /*
    Accumulation
    */
    Fbo::SharedPtr                  m_AccumFbo;
    Texture::SharedPtr              m_AccumRT;
    Texture::SharedPtr              m_AccumHistoryRT;
    FullScreenPass::SharedPtr       m_AccumPass;
    uint32_t                        m_AccumFrameCount = 1;

    /*
    Composite
    */
    Fbo::SharedPtr                  m_CompositeFbo;
    Texture::SharedPtr              m_CompositeColorRT;
    FullScreenPass::SharedPtr       m_CompositePass;

    /*
    Post Processing
    */
    FullScreenPass::SharedPtr       m_PostProcessingPass;

    /*
    Gerneal
    */
    Scene::SharedPtr                m_scene;
    Sampler::SharedPtr              m_linearSampler;
    Sampler::SharedPtr              m_pointSampler;

    float m_width, m_height;
};
