#include <metal_stdlib>
using namespace metal;

struct PreviewUniforms {
    float gain;
    float nightRed;
    float centerX;
    float centerY;
    float loupeZoom;
    float outWidth;
    float outHeight;
    float inWidth;
    float inHeight;
};

struct StackUniforms {
    float shiftX;
    float shiftY;
    float cosTheta;
    float sinTheta;
    float centerX;
    float centerY;
    float weight;
};

struct StretchUniforms {
    float invFrameCount;
    float applyStretch;
    float beta;
    float floorLevel;
};

struct SimSkyUniforms {
    float width;
    float height;
    float focusSigma;
    float skyScale;
    float starScale;
    float shiftX;
    float shiftY;
};

// 1. Real-time low-light boosted camera preview + optional 10x loupe region
kernel void livePreviewBoost(
    texture2d<float, access::sample> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant PreviewUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= uint(u.outWidth) || gid.y >= uint(u.outHeight)) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float outAspect = u.outWidth / max(u.outHeight, 1.0f);
    float inAspect  = u.inWidth  / max(u.inHeight,  1.0f);

    float2 uv = (float2(gid) + 0.5f) / float2(u.outWidth, u.outHeight);

    // Aspect-fill mapping from input camera texture to display drawable
    if (inAspect > outAspect) {
        float scale = outAspect / inAspect;
        uv.x = 0.5f + (uv.x - 0.5f) * scale;
    } else {
        float scale = inAspect / outAspect;
        uv.y = 0.5f + (uv.y - 0.5f) * scale;
    }

    // Optional digital zoom / focus loupe magnification around center
    if (u.loupeZoom > 1.01f) {
        float2 centerUV = float2(u.centerX, u.centerY);
        uv = centerUV + (uv - centerUV) / u.loupeZoom;
    }

    float4 col = inTex.sample(s, uv);
    float3 rgb = col.rgb;

    // Gentle low-light screen preview boost (never affects RAW DNG)
    if (u.gain > 1.05f) {
        float lum = dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
        float boosted = asinh(u.gain * 2.2f * lum) / asinh(u.gain * 2.2f);
        float scale = (lum > 1e-5f) ? (boosted / lum) : u.gain;
        rgb = clamp(rgb * mix(1.0f, scale, 0.85f), 0.0f, 1.0f);
    }

    // Night Vision Red filter on preview if active
    if (u.nightRed > 0.5f) {
        float lum = dot(rgb, float3(0.299f, 0.587f, 0.114f));
        rgb = float3(lum, lum * 0.10f, lum * 0.06f);
    }

    outTex.write(float4(rgb, 1.0f), gid);
}

// 2. Align & accumulate raw linear sub-frames with translation + rotation around sensor center
kernel void stackShiftAccumulate(
    texture2d<float, access::sample> inTex [[texture(0)]],
    texture2d<float, access::read> accTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant StackUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint w = outTex.get_width();
    uint h = outTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    constexpr sampler s(coord::pixel, address::clamp_to_zero, filter::linear);

    float dx = float(gid.x) - u.centerX;
    float dy = float(gid.y) - u.centerY;

    // Inverse transform from reference canvas -> subframe coordinates
    float rx =  u.cosTheta * dx + u.sinTheta * dy + u.centerX + u.shiftX;
    float ry = -u.sinTheta * dx + u.cosTheta * dy + u.centerY + u.shiftY;

    float4 sampleVal = inTex.sample(s, float2(rx + 0.5f, ry + 0.5f));
    float valid = (rx >= 1.0f && rx < float(w) - 1.0f && ry >= 1.0f && ry < float(h) - 1.0f) ? 1.0f : 0.0f;

    float4 prev = accTex.read(gid);
    float4 next = prev + float4(sampleVal.rgb * valid * u.weight, valid * u.weight);
    outTex.write(next, gid);
}

// 3. Normalize accumulated stack & optionally apply natural Arcsinh preview stretch
kernel void stackNormalizeStretch(
    texture2d<float, access::read> sumTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant StretchUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    float4 acc = sumTex.read(gid);
    float wSum = max(acc.a, 1e-5f);
    float3 lin = max(acc.rgb / wSum, 0.0f);

    if (u.applyStretch > 0.5f) {
        // Gentle astro Arcsinh curve on display preview/export while preserving star color ratios
        float lum = max(dot(lin, float3(0.2126f, 0.7152f, 0.0722f)), 1e-7f);
        float target = asinh(u.beta * lum) / asinh(u.beta * 0.90f);
        float3 col = clamp(lin * (target / lum), 0.0f, 1.0f);
        col = u.floorLevel + (1.0f - u.floorLevel) * col;
        outTex.write(float4(col, 1.0f), gid);
    } else {
        outTex.write(float4(lin, 1.0f), gid);
    }
}

// 4. Simulator Virtual Night Sky Generator (star PSF responds dynamically to lensPosition / ISO / drift!)
kernel void renderSimulatedNightSky(
    texture2d<float, access::write> outTex [[texture(0)]],
    constant SimSkyUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= uint(u.width) || gid.y >= uint(u.height)) return;

    float2 p = float2(gid);
    float nx = p.x / u.width;
    float ny = p.y / u.height;

    // Gentle sky gradient + faint diagonal simulated star cloud
    float cloudBand = exp(-pow((ny - (0.58f - 0.35f * nx)) / 0.16f, 2.0f));
    float3 skyBg = (float3(0.025f, 0.028f, 0.036f) + float3(0.042f, 0.035f, 0.026f) * cloudBand) * u.skyScale;

    // Subtle hillside silhouette on bottom 12%
    float hill = 0.87f + 0.03f * sin(nx * 9.0f) + 0.015f * cos(nx * 23.0f);
    if (ny > hill) {
        outTex.write(float4(float3(0.015f, 0.014f, 0.012f), 1.0f), gid);
        return;
    }

    float3 col = skyBg;
    // 14 deterministic bright & faint simulated stars centered around frame center so focus sweep tracks center ROI!
    const float2 starCoords[14] = {
        float2(0.50f, 0.50f), float2(0.46f, 0.48f), float2(0.54f, 0.52f), float2(0.48f, 0.54f),
        float2(0.52f, 0.45f), float2(0.42f, 0.46f), float2(0.58f, 0.48f), float2(0.35f, 0.36f),
        float2(0.65f, 0.38f), float2(0.28f, 0.58f), float2(0.72f, 0.60f), float2(0.44f, 0.30f),
        float2(0.60f, 0.25f), float2(0.22f, 0.28f)
    };
    const float3 starCols[14] = {
        float3(0.95f, 0.97f, 1.00f), float3(1.00f, 0.78f, 0.45f), float3(0.72f, 0.88f, 1.00f), float3(1.00f, 0.94f, 0.80f),
        float3(0.85f, 0.92f, 1.00f), float3(0.95f, 0.80f, 0.55f), float3(0.75f, 0.88f, 1.00f), float3(1.00f, 0.95f, 0.88f),
        float3(0.78f, 0.90f, 1.00f), float3(1.00f, 0.84f, 0.58f), float3(0.90f, 0.94f, 1.00f), float3(0.95f, 0.82f, 0.60f),
        float3(0.80f, 0.92f, 1.00f), float3(1.00f, 0.92f, 0.75f)
    };
    const float starBr[14] = { 1.4f, 1.1f, 1.0f, 0.85f, 0.80f, 0.75f, 0.90f, 0.95f, 0.85f, 0.70f, 0.80f, 0.65f, 0.90f, 0.80f };

    float s = max(1.2f, u.focusSigma);
    float inv2s2 = 0.5f / (s * s);
    float peakNorm = 1.8f / (s * 0.75f); // Total energy conserves -> crisp stars have much higher peak intensity!

    for (int i = 0; i < 14; ++i) {
        float2 sp = float2(starCoords[i].x * u.width + u.shiftX, starCoords[i].y * u.height + u.shiftY);
        float2 d = p - sp;
        float r2 = dot(d, d);
        if (r2 < s * s * 16.0f) {
            col += starCols[i] * (starBr[i] * peakNorm * u.starScale * exp(-r2 * inv2s2));
        }
    }

    // Subtle deterministic sensor noise
    uint h = (gid.x * 374761393u + gid.y * 668265263u + uint(abs(u.shiftX) * 100.0f));
    h = (h ^ (h >> 13)) * 1274126177u;
    float noise = (float(h & 0xFFu) / 255.0f - 0.5f) * 0.015f;
    col = clamp(col + noise, 0.0f, 1.0f);

    outTex.write(float4(col, 1.0f), gid);
}
