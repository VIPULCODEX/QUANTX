#version 460 core
#include <flutter/runtime_effect.glsl>

// Liquid glass — refraction of the backdrop through a rounded-rect lens.
//
// Ported in technique (not code) from the Compose Multiplatform approach used
// by Kyant0/AndroidLiquidGlass and Backdrop, which are Kotlin and cannot be
// consumed from Flutter. What ports is the maths: build a signed distance
// field for the panel, treat its edge falloff as a lens surface, derive a
// normal from the SDF gradient, and offset the sample coordinate along it.
//
// This is real refraction: light paths bend near the rim so the background
// visibly distorts, rather than merely blurring. Unlike Apple's Liquid Glass it
// cannot see the wallpaper behind the window or react to device motion — only
// what this app itself painted underneath.
//
// Runs as an ImageFilter.shader inside a BackdropFilter, which is Impeller-only
// (the Android default since Flutter 3.27).
//
// CONTRACT enforced by ImageFilter.shader: the first uniform must be a vec2,
// and at least one sampler must be present. Uniform order here matches the
// setFloat() indices on the Dart side, so do not reorder without updating both.

uniform vec2  uSize;        // float 0,1 — filtered region, in pixels
uniform float uRadius;      // float 2   — corner radius, pixels
uniform float uRefract;     // float 3   — max edge displacement, pixels
uniform float uThickness;   // float 4   — width of the refracting rim, pixels
uniform float uSpecular;    // float 5   — highlight intensity, 0..1
uniform sampler2D uTexture; // sampler 0 — the backdrop snapshot

out vec4 fragColor;

// Signed distance to a rounded box. Negative inside, zero on the edge.
float sdRoundedBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 frag   = FlutterFragCoord().xy;
    vec2 center = uSize * 0.5;
    vec2 p      = frag - center;

    float r = min(uRadius, min(uSize.x, uSize.y) * 0.5);
    float d = sdRoundedBox(p, uSize * 0.5, r);

    // Outside the panel: pass the backdrop through untouched.
    if (d > 0.0) {
        fragColor = texture(uTexture, frag / uSize);
        return;
    }

    // Surface normal from the SDF gradient. Finite differences are enough at
    // this scale and avoid an analytic derivative per corner case.
    float e = 1.0;
    vec2 grad = vec2(
        sdRoundedBox(p + vec2(e, 0.0), uSize * 0.5, r) -
        sdRoundedBox(p - vec2(e, 0.0), uSize * 0.5, r),
        sdRoundedBox(p + vec2(0.0, e), uSize * 0.5, r) -
        sdRoundedBox(p - vec2(0.0, e), uSize * 0.5, r)
    );
    vec2 normal = normalize(grad + vec2(1e-6));

    // Depth into the glass, 0 at the rim rising to 1 at the interior edge of
    // the rim band. Squared so the bend concentrates near the boundary the way
    // a real bevelled edge behaves, leaving the middle of the panel flat.
    float depth = clamp(-d / max(uThickness, 1.0), 0.0, 1.0);
    float bend  = (1.0 - depth) * (1.0 - depth);

    // Refract: walk the sample point along the inward normal.
    vec2 offset = normal * bend * uRefract;
    vec2 uv     = clamp((frag + offset) / uSize, vec2(0.0), vec2(1.0));

    // Slight per-channel divergence reads as dispersion through thick glass.
    // Kept small; overdone chromatic aberration looks like a broken display.
    float disp = bend * uRefract * 0.06;
    vec2 uvR = clamp((frag + offset + normal * disp) / uSize, vec2(0.0), vec2(1.0));
    vec2 uvB = clamp((frag + offset - normal * disp) / uSize, vec2(0.0), vec2(1.0));

    vec4 refracted = vec4(
        texture(uTexture, uvR).r,
        texture(uTexture, uv ).g,
        texture(uTexture, uvB).b,
        texture(uTexture, uv ).a
    );

    // Specular rim: a fixed light from the upper-left catching the bevel.
    // Not motion-reactive — that needs sensor input the compositor does not
    // provide here.
    vec2  lightDir = normalize(vec2(-0.55, -0.83));
    float facing   = max(dot(normal, lightDir), 0.0);
    float rim      = pow(facing, 3.0) * bend * uSpecular;

    fragColor = refracted + vec4(vec3(rim), 0.0);
}
