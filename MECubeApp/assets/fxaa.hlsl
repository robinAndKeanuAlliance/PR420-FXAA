#pragma warning(disable: 4000)
#include "ShaderCommon.hlsl"

SamplerState g_Sampler : register(s0);
Texture2D g_OffscreenTexture : register(t0);

static const float FXAA_EDGE_THRESHOLD_MIN = 0.0625;  //minimum edge detection threshold
static const float FXAA_SEARCH_STEPS = 8;  //mumber of searches step
static const float FXAA_SEARCH_THRESHOLD = 0.25;  // search acceleration

cbuffer PostEffectCB : register(b2)
{
    float g_value;
};

// tex -> input textur. hier der gerenderte screen
// samp -> sampler state used fotr sampling. this defines how texture is sampled idk man
// ub -> uv coordinate of current pixel being processed
// rcpFrame -> texture dimensions / size of pixels on screen used for pixel sampling offset to get neighbors
float4 FXAA(Texture2D tex, SamplerState samp, float2 uv, float2 rcpFrame)
{
    if (g_value == 0)
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

    // modes 2 and 3: Display detected edges without and with direction
    if (g_value == 2)
        return float4(abs(dir), 0.0, 1.0);
    if (g_value == 3)
        return float4(dir, 0.0, 1.0);

    //reduce edge direction to not have big values
    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_SEARCH_THRESHOLD), FXAA_EDGE_THRESHOLD_MIN);

    // mode 4: skip edge direction reduction to show this makes result better
    if (g_value != 4)
        dir *= (1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce));
    else
        dir *= (1.0 / min(abs(dir.x), abs(dir.y)));

    dir = min(float2(FXAA_SEARCH_STEPS, FXAA_SEARCH_STEPS),
        max(float2(-FXAA_SEARCH_STEPS, -FXAA_SEARCH_STEPS),
            dir)) * rcpFrame;

    //sample different pixels in edge direction and avarage them to get blended colors
    //rgbA average of two points along the direction
    //rgbB average of rgbA and two different samples against the direction of the edge
    //rgbB can potentially get a better result because its smoother but can introduce artifacts
    float3 rgbA = 0.5 * (
        tex.SampleLevel(samp, uv + dir * (1.0 / 3.0 - 0.5), 0.0).rgb +
        tex.SampleLevel(samp, uv + dir * (2.0 / 3.0 - 0.5), 0.0).rgb);
    float3 rgbB = rgbA * 0.5 + 0.25 * (
        tex.SampleLevel(samp, uv + dir * -0.5, 0.0).rgb +
        tex.SampleLevel(samp, uv + dir * 0.5, 0.0).rgb);

    // mode 5: always use rgbA color
    if (g_value == 5)
        return float4(rgbA, 1.0);

    // mode 6: always use rgbB color
    if (g_value == 6)
        return float4(rgbB, 1.0);

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
