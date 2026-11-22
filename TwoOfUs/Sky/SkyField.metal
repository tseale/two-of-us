#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The sky field's print: `SkyFieldTexture`'s negative (the air in OKLab on a
// 2-point grid, before the room's tone) brought to the display. The hush and
// the room's depth arrive as uniforms and are applied in float, ahead of the
// one dither, so a change of tone never steps a near-black sky by a whole
// level (hill-painted.md, "SwiftUI port", note 10). The arithmetic is
// `Air.shown` and `OKLab.srgb(.sky)`; keep the three in step.

static inline float3 skyLinear(float lightness, float a, float b) {
    float l = lightness + 0.3963377774 * a + 0.2158037573 * b;
    float m = lightness - 0.1055613458 * a - 0.0638541728 * b;
    float s = lightness - 0.0894841775 * a - 1.291485548 * b;
    l = l * l * l;
    m = m * m * m;
    s = s * s * s;
    return float3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s);
}

static inline bool skyFits(float3 c) {
    return all(c >= float3(-1e-4)) && all(c <= float3(1.0001));
}

static inline float skyGamma(float c) {
    c = saturate(c);
    return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

// 0 … 1 from a device pixel: a small integer hash, for the dither only.
static inline float skyHash(uint2 p, uint salt) {
    uint h = p.x * 0x9E3779B1u ^ (p.y * 0x85EBCA77u) ^ (salt * 0xC2B2AE3Du);
    h ^= h >> 15;
    h *= 0x2C1B3C6Du;
    h ^= h >> 12;
    h *= 0x297A2D39u;
    h ^= h >> 15;
    return float(h & 0xFFFFFFu) / 16777216.0;
}

// grid:   columns, rows of one half
// tone:   presence (the hush), depth (the room), dark appearance, how far the pale page pulls
// light:  chroma kept at no presence (pale page), the brush's strength, the night, the lift behind the crown
// place:  the horizon's y in the plane, points the twilight spans, the tree's x in the plane, its height
// screen: pixels per point, a probe (0 the sky; 1 the texel as it arrives; 2 flat half grey; 3 the low bits of lightness)
[[ stitchable ]] half4 skyField(float2 position, half4 color, texture2d<half> negative,
                                float2 grid, float4 tone, float4 light, float4 place, float2 screen) {
    constexpr sampler bilinear(address::clamp_to_edge, filter::linear);
    float tall = grid.y * 2.0 + 2.0;
    float2 uv = (position / 2.0 + 0.5) / float2(grid.x, tall);
    half4 texel = negative.sample(bilinear, uv);
    float drag = float(negative.sample(bilinear, uv + float2(0.0, (grid.y + 2.0) / tall)).r) - 0.5;

    if (screen.y > 2.5) {
        float low = fract(float(texel.r) * 256.0);
        return half4(half3(low), 1.0);
    }
    if (screen.y > 1.5) { return half4(0.5, 0.5, 0.5, 1.0); }
    if (screen.y > 0.5) { return half4(texel.rgb, 1.0); }

    float lightness = float(texel.r);
    float a = float(texel.g) - 0.5;
    float b = float(texel.b) - 0.5;
    float presence = tone.x;
    float depth = tone.y;
    bool dark = tone.z > 0.5;
    float elevation = (place.x - position.y) / place.y;

    // The hand: long drags of the brush, quieter under the hush.
    lightness += drag * light.y * (0.45 + 0.55 * presence);

    if (dark) {
        lightness *= 1.0 - 0.12 * (1.0 - presence);
        float chroma = (0.4 + 0.6 * presence) * (1.0 - 0.12 * depth);
        a *= chroma;
        b *= chroma;
        lightness *= 1.0 - 0.14 * depth;
        // The dimmed room deepens the sky overhead, not the last light
        // along the horizon.
        float keep = light.z * (1.0 / (1.0 - 0.14 * depth) - 1.0) * 0.9;
        lightness += lightness * keep * exp(-max(0.0, elevation) / 0.3);
        if (light.w > 0.0) {
            float crown = place.w * 0.62 / place.y;
            float ux = (position.x - place.z) / (place.w * 0.95);
            float ue = (max(0.0, elevation) - crown * 0.72) / (crown * 0.55);
            lightness += light.w * exp(-ux * ux - ue * ue);
        }
    } else {
        lightness += (0.9612 - lightness) * tone.w * (1.0 - presence);
        float chroma = (light.x + (1.0 - light.x) * presence) * (1.0 - 0.25 * depth);
        a *= chroma;
        b *= chroma;
        lightness -= 0.012 * depth;
    }

    // Into sRGB, giving up chroma and never hue (`OKLab.srgb(.sky)`).
    lightness = saturate(lightness);
    float3 rgb = skyLinear(lightness, a, b);
    if (!skyFits(rgb)) {
        float low = 0.0;
        float high = 1.0;
        for (int i = 0; i < 14; i++) {
            float share = (low + high) * 0.5;
            if (skyFits(skyLinear(lightness, a * share, b * share))) { low = share; } else { high = share; }
        }
        rgb = skyLinear(lightness, a * low, b * low);
    }
    float3 shown = float3(skyGamma(rgb.r), skyGamma(rgb.g), skyGamma(rgb.b));

    // One triangular dither, a level wide, at the device pixel.
    uint2 pixel = uint2(position * screen.x);
    float3 noise = float3(skyHash(pixel, 1u) + skyHash(pixel, 2u),
                          skyHash(pixel, 3u) + skyHash(pixel, 4u),
                          skyHash(pixel, 5u) + skyHash(pixel, 6u)) - 1.0;
    shown += noise * (0.92 / 255.0);
    return half4(half3(saturate(shown)), 1.0);
}
