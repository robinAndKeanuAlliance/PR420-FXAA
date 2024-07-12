//-----------------------------------------------------------------------------
// Copyright (c) 2022 Sascha Worszeck. All Rights Reserved.
//-----------------------------------------------------------------------------
#pragma warning(disable: 4000)
#include "ShaderCommon.hlsl"

SamplerState g_Sampler : register(s0);
Texture2D g_OffscreenTexture : register(t0);

// FXAA parameters (adjust these as needed)
static const float FXAA_REDUCE_MIN = 1 / 128.0;  // Minimum contrast for FXAA processing
static const float FXAA_REDUCE_MUL = 1 / 8.0;    // Reduce multiplier
static const float FXAA_SPAN_MAX = 8;            // Maximum span for FXAA filtering

cbuffer PostEffectCB : register(b2)
{
    float g_value;
};

float4 FXAA(Texture2D tex, SamplerState samp, float2 uv, float2 texSize)
{
    if (g_value >= 1)
        return tex.Sample(samp, uv);

    float2 rcpFrame = 1.0 / texSize;

    float3 rgbNW = tex.SampleLevel(samp, uv + float2(-1.0, -1.0) * rcpFrame, 0.0).rgb;
    float3 rgbNE = tex.SampleLevel(samp, uv + float2(1.0, -1.0) * rcpFrame, 0.0).rgb;
    float3 rgbSW = tex.SampleLevel(samp, uv + float2(-1.0, 1.0) * rcpFrame, 0.0).rgb;
    float3 rgbSE = tex.SampleLevel(samp, uv + float2(1.0, 1.0) * rcpFrame, 0.0).rgb;
    float3 rgbM = tex.SampleLevel(samp, uv, 0.0).rgb;

    float3 luma = float3(0.299, 0.587, 0.114);
    float lumaNW = dot(rgbNW, luma);
    float lumaNE = dot(rgbNE, luma);
    float lumaSW = dot(rgbSW, luma);
    float lumaSE = dot(rgbSE, luma);
    float lumaM = dot(rgbM, luma);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    float lumaRange = lumaMax - lumaMin;

    if (lumaRange < max(FXAA_REDUCE_MIN, lumaMax * FXAA_REDUCE_MUL))
    {
        return float4(rgbM, 1.0);
    }

    float2 dir = float2(0.0, 0.0);
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(float2(FXAA_SPAN_MAX, FXAA_SPAN_MAX),
        max(float2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), dir * rcpDirMin)) * rcpFrame;

    float3 rgbA = 0.5 * (
        tex.SampleLevel(samp, uv + dir * (1.0 / 3.0 - 0.5), 0.0).rgb +
        tex.SampleLevel(samp, uv + dir * (2.0 / 3.0 - 0.5), 0.0).rgb);
    float3 rgbB = rgbA * 0.5 + 0.25 * (
        tex.SampleLevel(samp, uv + dir * -0.5, 0.0).rgb +
        tex.SampleLevel(samp, uv + dir * 0.5, 0.0).rgb);

    float lumaB = dot(rgbB, luma);
    if (lumaB < lumaMin || lumaB > lumaMax)
    {
        return float4(rgbA, 1.0);
    }
    return float4(rgbB, 1.0);
}

float4 PS_Main(PS_INPUT_POSTEFFECT_PARAM IN) : SV_TARGET
{
    float2 texSize;
    g_OffscreenTexture.GetDimensions(texSize.x, texSize.y);

    float4 color = FXAA(g_OffscreenTexture, g_Sampler, IN.UV, texSize);

    return color;
}