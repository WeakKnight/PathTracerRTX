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
#include "PathTracer.h"

#define SCREEN_WIDTH 1600
#define SCREEN_HEIGHT 900

uint32_t mSampleGuiWidth = 250;
uint32_t mSampleGuiHeight = 200;
uint32_t mSampleGuiPositionX = 20;
uint32_t mSampleGuiPositionY = 40;

static float s_exposure = 1.0f;
static bool s_enableGBufferDebug = false;
static int s_GBufferDebugType = 5;
static const std::string s_defaultScene =
"Arcade/Arcade.fscene";
// "SunTemple/SunTemple.fscene";

void PathTracer::LoadScene()
{
    m_scene = Scene::create(s_defaultScene);
    m_GBufferProgram->addDefines(m_scene->getSceneDefines());
    m_GBufferProgramVars = GraphicsVars::create(m_GBufferProgram->getReflector());

    m_scene->bindSamplerToMaterials(m_linearSampler);
    m_scene->setCameraController(Scene::CameraControllerType::FirstPerson);
    // m_scene->setCameraAspectRatio(m_width / m_height);
}

void PathTracer::CreateGBufferFBO()
{
    m_GBufferFbo = Fbo::create2D(m_width, m_height, ResourceFormat::RGBA16Float, ResourceFormat::D24UnormS8);

    m_GBufferAlbedoRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_GBufferSpecRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_GBufferPositionRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA32Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_GBufferNormalRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_GBufferExtraRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_GBufferEmissiveRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);

    m_GBufferDepthRT = Texture::create2D(m_width, m_height, ResourceFormat::D24UnormS8, 1U, 1U, nullptr, ResourceBindFlags::DepthStencil);

    m_GBufferFbo->attachColorTarget(m_GBufferAlbedoRT, 0);
    m_GBufferFbo->attachColorTarget(m_GBufferSpecRT, 1);
    m_GBufferFbo->attachColorTarget(m_GBufferPositionRT, 2);
    m_GBufferFbo->attachColorTarget(m_GBufferNormalRT, 3);
    m_GBufferFbo->attachColorTarget(m_GBufferExtraRT, 4);
    m_GBufferFbo->attachColorTarget(m_GBufferEmissiveRT, 5);
    
    m_GBufferFbo->attachDepthStencilTarget(m_GBufferDepthRT);
}

void PathTracer::CreateGBufferPipeline()
{
    CreateGBufferFBO();

    m_GBufferProgram = GraphicsProgram::createFromFile("PathTracer/GBuffer.ps.slang", "", "main");
    m_GBufferGraphicsState = GraphicsState::create();
    m_GBufferGraphicsState->setProgram(m_GBufferProgram);

    RasterizerState::Desc rasterStateDesc;
    rasterStateDesc.setCullMode(RasterizerState::CullMode::Back);
    m_GBufferRasterizerState = RasterizerState::create(rasterStateDesc);

    DepthStencilState::Desc depthStancilDesc;
    depthStancilDesc.setDepthFunc(ComparisonFunc::Less).setDepthEnabled(true);
    m_GBufferDepthStencilState = DepthStencilState::create(depthStancilDesc);
}

void PathTracer::CreateRTPipeline()
{
    RtProgram::Desc rtProgDesc;
    rtProgDesc.addShaderLibrary("PathTracer/Raytracing.rt.slang").setRayGen("rayGen");
    rtProgDesc.addHitGroup(0, "IndirectClosestHit", "IndirectAnyHit").addMiss(0, "IndirectMiss");
    rtProgDesc.addHitGroup(1, "", "ShadowAnyHit").addMiss(1, "ShadowMiss");

    rtProgDesc.addDefines(m_scene->getSceneDefines());
    rtProgDesc.setMaxTraceRecursionDepth(10);

    m_RaytraceProgram = RtProgram::create(rtProgDesc);
    m_RtVars = RtProgramVars::create(m_RaytraceProgram, m_scene);
    m_RaytraceProgram->setScene(m_scene);

    CreateRTRenderTarget();
}

void PathTracer::CreateAORenderTarget()
{
    m_AORT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource);
}

void PathTracer::CreateAOPipeline()
{
    RtProgram::Desc rtProgDesc;
    rtProgDesc.addShaderLibrary("PathTracer/AOTracing.rt.slang").setRayGen("AoRayGen");
    rtProgDesc.addHitGroup(0, "AoClosestHit", "AoAnyHit").addMiss(0, "AoMiss");
    rtProgDesc.addDefines(m_scene->getSceneDefines());
    rtProgDesc.setMaxTraceRecursionDepth(3); // 1 for calling TraceRay from RayGen, 1 for calling it from the primary-ray ClosestHitShader for reflections, 1 for reflection ray tracing a shadow ray

    m_AOProgram = RtProgram::create(rtProgDesc);
    m_AOVars = RtProgramVars::create(m_AOProgram, m_scene);
    m_AOProgram->setScene(m_scene);

    CreateAORenderTarget();
}

void PathTracer::AORender(RenderContext* pRenderContext)
{
    const float4 clearColor(0.0f, 0.0f, 0.0f, 0.0f);

    m_AOVars["RayGenCB"]["gFrameCount"] = m_FrameCount++;
    m_AOVars["RayGenCB"]["gAORadius"] = m_AORadius;
    m_AOVars["RayGenCB"]["gMinT"] = 1.0e-4f;
    m_AOVars["gPos"] = m_GBufferPositionRT;
    m_AOVars["gNorm"] = m_GBufferNormalRT;
    m_AOVars["gOutput"] = m_AORT;

    pRenderContext->clearUAV(m_AORT->getUAV().get(), clearColor);
    m_scene->raytrace(pRenderContext, m_AOProgram.get(), m_AOVars, uint3(m_width, m_height, 1));
}

void PathTracer::RaytraceRender(RenderContext* pRenderContext)
{
    const float4 clearColor(0.0f, 0.0f, 0.0f, 0.0f);

    auto cb = m_RtVars["PerFrameCB"];
    cb["invView"] = glm::inverse(m_scene->getCamera()->getViewMatrix());
    cb["viewportDims"] = float2(m_width, m_height);
    float fovY = focalLengthToFovY(m_scene->getCamera()->getFocalLength(), Camera::kDefaultFrameHeight);
    cb["tanHalfFovY"] = tanf(fovY * 0.5f);
    cb["gFrameCount"] = m_FrameCount++;
    cb["gMinT"] = 1.0e-4f;
    cb["gMaxDepth"] = m_MaxDepth;

    auto envMap = m_scene->getEnvironmentMap();
    m_RtVars["gEnvMap"] = envMap;

    m_RtVars["gPos"] = m_GBufferPositionRT;
    m_RtVars["gNorm"] = m_GBufferNormalRT;
    m_RtVars["gAlbedo"] = m_GBufferAlbedoRT;
    m_RtVars["gSpec"] = m_GBufferSpecRT;
    m_RtVars["gEmissive"] = m_GBufferEmissiveRT;

    m_RtVars->getRayGenVars()["gOutput"] = m_RaytraceRT;

    pRenderContext->clearUAV(m_RaytraceRT->getUAV().get(), clearColor);
    m_scene->raytrace(pRenderContext, m_RaytraceProgram.get(), m_RtVars, uint3(m_width, m_height, 1));
}

void PathTracer::CreateRTRenderTarget()
{
    m_RaytraceRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource);
}

void PathTracer::CreateAccumFBO()
{
    m_AccumFrameCount = 1;

    m_AccumFbo = Fbo::create2D(m_width, m_height, ResourceFormat::RGBA16Float);
    m_AccumRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_AccumFbo->attachColorTarget(m_AccumRT, 0);

    m_AccumHistoryRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
}

void PathTracer::CreateAccumPipeline()
{
    CreateAccumFBO();
    m_AccumPass = FullScreenPass::create("PathTracer/Accumulation.ps.slang", m_scene->getSceneDefines());
}

void PathTracer::CreateCompositeFBO()
{
    m_CompositeFbo = Fbo::create2D(m_width, m_height, ResourceFormat::RGBA16Float);
    m_CompositeColorRT = Texture::create2D(m_width, m_height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, ResourceBindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_CompositeFbo->attachColorTarget(m_CompositeColorRT, 0);
}

void PathTracer::CreateCompositePipeline()
{
    CreateCompositeFBO();
    m_CompositePass = FullScreenPass::create("PathTracer/Composite.ps.slang", m_scene->getSceneDefines());
}

void PathTracer::onLoad(RenderContext* pRenderContext)
{
    m_width = SCREEN_WIDTH;
    m_height = SCREEN_HEIGHT;

    auto now = std::chrono::high_resolution_clock::now();
    auto msTime = std::chrono::time_point_cast<std::chrono::milliseconds>(now);
    m_Rng = std::mt19937(uint32_t(msTime.time_since_epoch().count()));

    // Global Samplers
    Sampler::Desc samplerDesc;
    samplerDesc.setFilterMode(Sampler::Filter::Linear, Sampler::Filter::Linear, Sampler::Filter::Linear).setMaxAnisotropy(8);
    m_linearSampler = Sampler::create(samplerDesc);

    Sampler::Desc pointSamplerDesc;
    pointSamplerDesc.setFilterMode(Sampler::Filter::Point, Sampler::Filter::Point, Sampler::Filter::Point);
    m_pointSampler = Sampler::create(pointSamplerDesc);

    // Create PostProcessing Pass
    m_PostProcessingPass = FullScreenPass::create("PathTracer/PostProcessing.ps.slang");
    // m_PostProcessingPass->getVars()->
    CreateGBufferPipeline();
    LoadScene();
    CreateCompositePipeline();
    CreateRTPipeline();
    CreateAccumPipeline();
}

void PathTracer::onGuiRender(Gui* pGui)
{
    Gui::Window w(pGui, "Playground", { 250, 200 });
    //gpFramework->renderGlobalUI(pGui);
    //w.text("Hello from ProjectTemplate");
    w.slider("Exposure", s_exposure, 0.0f, 5.0f);
    w.checkbox("GBufferDebug", s_enableGBufferDebug);

    if (w.button("GBufferAlbedo"))
    {
        s_GBufferDebugType = 0;
    }
    if (w.button("GBufferSpec", true))
    {
        s_GBufferDebugType = 1;
    }
    if (w.button("GBufferPos", true))
    {
        s_GBufferDebugType = 2;
    }
    if (w.button("GBufferNormal", true))
    {
        s_GBufferDebugType = 3;
    }
    if (w.button("RayTracingResult", false))
    {
        s_GBufferDebugType = 4;
    }
}

void PathTracer::onFrameRender(RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo)
{
    float xJitter = (m_RngDist(m_Rng) - 0.5f) / m_width;
    float yJitter = (m_RngDist(m_Rng) - 0.5f) / m_height;
    m_scene->getCamera()->setJitter(xJitter, yJitter);
    m_scene->update(pRenderContext, gpFramework->getGlobalClock().getTime());

    const float4 clearColor(0.0f, 0.0f, 0.0f, 0.0f);

    if ((uint32_t)m_scene->getCamera()->getChanges() & (uint32_t)Camera::Changes::History)
    {
        m_AccumFrameCount = 1;
        pRenderContext->clearFbo(m_AccumFbo.get(), clearColor, 1.0f, 0, FboAttachmentType::All);
        pRenderContext->clearTexture(m_AccumHistoryRT.get());
    }

    // GBuffer

    pRenderContext->clearFbo(m_GBufferFbo.get(), clearColor, 1.0f, 0, FboAttachmentType::All);

    m_GBufferGraphicsState->setFbo(m_GBufferFbo);

    Scene::RenderFlags renderFlags = Scene::RenderFlags::UserRasterizerState;
    m_GBufferGraphicsState->setRasterizerState(m_GBufferRasterizerState);
    m_GBufferGraphicsState->setDepthStencilState(m_GBufferDepthStencilState);

    m_GBufferGraphicsState->setProgram(m_GBufferProgram);
    m_scene->render(pRenderContext, m_GBufferGraphicsState.get(), m_GBufferProgramVars.get(), renderFlags);

    // RayTrace

    RaytraceRender(pRenderContext);

    // Composite

    m_CompositePass->getVars()->setParameterBlock("gScene", m_scene->getParameterBlock());

    m_CompositePass->getVars()->setTexture("_GBufferAlbedo", m_GBufferAlbedoRT);
    m_CompositePass->getVars()->setTexture("_GBufferSpec", m_GBufferSpecRT);
    m_CompositePass->getVars()->setTexture("_GBufferPosition", m_GBufferPositionRT);
    m_CompositePass->getVars()->setTexture("_GBufferNormal", m_GBufferNormalRT);
    m_CompositePass->getVars()->setTexture("_GBufferExtra", m_GBufferExtraRT);
    m_CompositePass->getVars()->setTexture("_RayTraceResult", m_RaytraceRT);
    
    m_CompositePass->getVars()->setSampler("_linearSampler", m_linearSampler);
    m_CompositePass->getVars()->setSampler("_pointSampler", m_pointSampler);
    
    m_CompositePass["CompositeCB"]["enableDebug"] = s_enableGBufferDebug?1:0;
    m_CompositePass["CompositeCB"]["debugType"] = s_GBufferDebugType;
    
    if (s_enableGBufferDebug)
    {
        m_CompositePass->execute(pRenderContext, pTargetFbo);
    }
    else
    {
        m_CompositePass->execute(pRenderContext, m_CompositeFbo);

        // Accumulate

        m_AccumPass->getVars()->setTexture("_LinearResult", m_CompositeColorRT);
        m_AccumPass->getVars()->setTexture("_AccumHistory", m_AccumHistoryRT);
        m_AccumPass->getVars()->setSampler("_pointSampler", m_pointSampler);

        m_AccumPass["AccumCB"]["AccumFrameIndex"] = m_AccumFrameCount;

        m_AccumPass->execute(pRenderContext, m_AccumFbo);

        pRenderContext->copyResource(m_AccumHistoryRT.get(), m_AccumRT.get());

        m_AccumFrameCount++;

        // Post Processing

        m_PostProcessingPass->getVars()->setTexture("_texLinearResult", m_AccumRT);
        m_PostProcessingPass->getVars()->setSampler("_linearSampler", m_linearSampler);

        m_PostProcessingPass["PPCB"]["exposure"] = s_exposure;
        m_PostProcessingPass->execute(pRenderContext, pTargetFbo);
    }
}

void PathTracer::onShutdown()
{
}

bool PathTracer::onKeyEvent(const KeyboardEvent& keyEvent)
{
    if (m_scene && m_scene->onKeyEvent(keyEvent)) return true;

    return false;
}

bool PathTracer::onMouseEvent(const MouseEvent& mouseEvent)
{
    return m_scene ? m_scene->onMouseEvent(mouseEvent) : false;
}

void PathTracer::onHotReload(HotReloadFlags reloaded)
{
}

void PathTracer::onResizeSwapChain(uint32_t width, uint32_t height)
{
    m_width = width;
    m_height = height;

    // m_scene->setCameraAspectRatio(width / height);

    CreateGBufferFBO();
    CreateCompositeFBO();
    CreateRTRenderTarget();
    CreateAccumFBO();
}

int WINAPI WinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ LPSTR lpCmdLine, _In_ int nShowCmd)
{
    PathTracer::UniquePtr pRenderer = std::make_unique<PathTracer>();
    SampleConfig config;
    config.windowDesc.title = "RealtimeRaytracing";
    config.windowDesc.resizableWindow = true;
    config.windowDesc.width = SCREEN_WIDTH;
    config.windowDesc.height = SCREEN_HEIGHT;

    Sample::run(config, pRenderer);
    return 0;
}
