#pragma warning(disable: 4000)
#include "ShaderCommon.hlsl"

SamplerState g_Sampler : register(s0);
Texture2D g_OffscreenTexture : register(t0);

static const float FXAA_EDGE_THRESHOLD = 0.125;  // edge detection threshold
static const float FXAA_EDGE_THRESHOLD_MIN = 0.0625;  //minimum edge detection threshold
static const float FXAA_SEARCH_STEPS = 8;  //mumber of searches step
static const float FXAA_SEARCH_THRESHOLD = 0.25;  // search acceleration
static const float FXAA_SUBPIX_CAP = 0.75;  // subpixel alliasing removal amount
static const float FXAA_SUBPIX_TRIM = 0.05;  // subnpixel alliasing removal trimming

cbuffer PostEffectCB : register(b2)
{
    float g_value;
};

float4 FXAA(Texture2D tex, SamplerState samp, float2 uv, float2 rcpFrame)
{
    if (g_value >= 1)
        return tex.Sample(samp, uv);

    //get color value from current pixel and its neighbors
    float3 rgbNW = tex.SampleLevel(samp, uv + float2(-1.0, -1.0) * rcpFrame, 0.0).rgb;
    float3 rgbNE = tex.SampleLevel(samp, uv + float2(1.0, -1.0) * rcpFrame, 0.0).rgb;
    float3 rgbSW = tex.SampleLevel(samp, uv + float2(-1.0, 1.0) * rcpFrame, 0.0).rgb;
    float3 rgbSE = tex.SampleLevel(samp, uv + float2(1.0, 1.0) * rcpFrame, 0.0).rgb;
    float3 rgbM = tex.SampleLevel(samp, uv, 0.0).rgb;

    //get luma value from current pixel and neighbors using rgb to grayscale coeffiecients
    float3 luma = float3(0.299, 0.587, 0.114);
    float lumaNW = dot(rgbNW, luma);
    float lumaNE = dot(rgbNE, luma);
    float lumaSW = dot(rgbSW, luma);
    float lumaSE = dot(rgbSE, luma);
    float lumaM = dot(rgbM, luma);

    //luma min and max values are calculated
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    //direction of of edge is calculated using luma Min and max
    float2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    //reduce edge direction to not have big values
    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_SEARCH_THRESHOLD), FXAA_EDGE_THRESHOLD_MIN);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);

    dir = min(float2(FXAA_SEARCH_STEPS, FXAA_SEARCH_STEPS),
        max(float2(-FXAA_SEARCH_STEPS, -FXAA_SEARCH_STEPS),
            dir * rcpDirMin)) * rcpFrame;

    //sample 2 different pixels in edge direction to get 2 different colors
    //rgbA average of two points along the direction
    //rgbB average of rgbA and two different samples against the direction of the edge
    //rgbB can potentially get a better result because its smoother but can introduce artifacts
    float3 rgbA = 0.5 * (
        tex.SampleLevel(samp, uv + dir * (1.0 / 3.0 - 0.5), 0.0).rgb +
        tex.SampleLevel(samp, uv + dir * (2.0 / 3.0 - 0.5), 0.0).rgb);
    float3 rgbB = rgbA * 0.5 + 0.25 * (
        tex.SampleLevel(samp, uv + dir * -0.5, 0.0).rgb +
        tex.SampleLevel(samp, uv + dir * 0.5, 0.0).rgb);


    //compare luma values to pick correct values
    //if rbgB is outside of luma range rgbB might introduce artifacts so rgbA is used
    //general rule sharp edge rgbA is used
    float lumaB = dot(rgbB, luma);

    if (lumaB < lumaMin || lumaB > lumaMax)
        return float4(rgbA, 1.0);
    else
        return float4(rgbB, 1.0);
}

float4 PS_Main(PS_INPUT_POSTEFFECT_PARAM IN) : SV_TARGET
{
    float2 texSize;
    g_OffscreenTexture.GetDimensions(texSize.x, texSize.y);
    float2 rcpFrame = 1.0 / texSize;

    return FXAA(g_OffscreenTexture, g_Sampler, IN.UV, rcpFrame);
}