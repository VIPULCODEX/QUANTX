#version 460 core
#include <flutter/runtime_effect.glsl>

// Liquid glass — refraction of the backdrop through a rounded-rect lens.
//
// Technique (not code) follows the Compose Multiplatform approach used by
// Kyant0/AndroidLiquidGlass and Backdrop, which are Kotlin and cannot be
// consumed from Flutter. What ports is the maths: build a signed distance
// field for the panel, treat its edge falloff as a lens surface, derive a
// normal from the SDF gradient, and offset the sample coordinate along it.
//
// Real refraction: light paths bend near the rim so the background visibly
// distorts, rather than merely blurring. Unlike Apple's Liquid Glass it cannot
// see the wallpaper behind the window or react to device motion — only what
// this app itself painted underneath.
//
// ---------------------------------------------------------------------------
// ENGINE CONTRACT (ImageFilter.shader) — violating any of these silently
// produces a no-op that looks exactly like a plain blur:
//
//   * float 0,1 (the first vec2) are set BY THE ENGINE to the bound texture
//     size. Dart must NOT write them. v1.4.0 did, which is why nothing moved.
//   * sampler 0 is set by the engine to the filter input.
//   * uSize is in DEVICE pixels. Every length arriving from Dart is in LOGICAL
//     pixels, so it must be scaled by uDpr before being compared against a
//     distance derived from uSize. v1.4.0 skipped this, shrinking the rim to a
//     third of its intended width — visible only as "looks the same as before".
//   * On OpenGLES the sampled texture is y-flipped; Vulkan is not.
//
// Uniform order below fixes the float indices used by liquid_glass.dart.
// Do not reorder without updating both sides.
// ---------------------------------------------------------------------------

uniform vec2  uSize;        // float 0,1 — ENGINE SET. texture size, device px
uniform float uRadius;      // float 2   — corner radius, logical px
uniform float uRefract;     // float 3   — max edge displacement, logical px
uniform float uThickness;   // float 4   — width of the refracting rim, logical
uniform float uSpecular;    // float 5   — highlight intensity, 0..1
uniform float uDpr;         // float 6   — device pixel ratio
uniform float uDebug;       // float 7   — >0.5 renders the lens field directly
uniform float uBlur;        // float 8   — frost radius, logical px
uniform sampler2D uTexture; // sampler 0 — ENGINE SET. the backdrop snapshot

out vec4 fragColor;

// Sample the backdrop in normalised space, compensating for the GLES y-flip.
vec4 sampleBackdrop(vec2 uv) {
    uv = clamp(uv, vec2(0.0), vec2(1.0));
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return texture(uTexture, uv);
}

// Frost, done inside the shader rather than by composing an ImageFilter.blur
// in front of it. Composing is what flutter#170820 was about: the blur expands
// the filtered coverage, so the texture handed to the shader stops matching the
// panel rect and the SDF below is computed against the wrong box. Keeping the
// blur here preserves the invariant that the bound texture IS the panel.
//
// Two rings of six taps plus the centre. Deliberately no chromatic dispersion:
// under a translucent tint it is imperceptible, and it tripled the tap count.
vec4 frost(vec2 centre, float radiusPx) {
    if (radiusPx < 0.5) return sampleBackdrop(centre / uSize);

    vec4 sum = sampleBackdrop(centre / uSize);
    float wsum = 1.0;

    for (int i = 0; i < 6; i++) {
        float a = float(i) * 1.0471975 + 0.3926990;   // 60° apart, offset ring
        vec2  dir = vec2(cos(a), sin(a));
        sum  += sampleBackdrop((centre + dir * radiusPx * 0.55) / uSize) * 0.8;
        sum  += sampleBackdrop((centre + dir * radiusPx) / uSize) * 0.5;
        wsum += 1.3;
    }
    return sum / wsum;
}

// Signed distance to a rounded box. Negative inside, zero on the edge.
float sdRoundedBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 frag = FlutterFragCoord().xy;

    // The filtered region IS the panel: a ClipRRect bounds the BackdropFilter,
    // so the bound texture covers exactly the widget rect. Panel geometry
    // therefore derives from uSize rather than anything passed in — which also
    // removes any question about which coordinate space Dart was measuring in.
    vec2  halfExtent   = uSize * 0.5;
    vec2  p      = frag - halfExtent;
    float dpr    = max(uDpr, 1.0);

    // Logical -> device before touching an SDF measured in device pixels.
    float radius    = min(uRadius * dpr, min(uSize.x, uSize.y) * 0.5);
    float thickness = max(uThickness * dpr, 1.0);
    float refract   = uRefract * dpr;

    float d = sdRoundedBox(p, halfExtent, radius);

    // Outside the panel: pass the backdrop through untouched.
    if (d > 0.0) {
        fragColor = sampleBackdrop(frag / uSize);
        return;
    }

    // Surface normal from the SDF gradient. Finite differences are enough at
    // this scale and avoid an analytic derivative per corner case.
    float e = 1.0;
    vec2 grad = vec2(
        sdRoundedBox(p + vec2(e, 0.0), halfExtent, radius) -
        sdRoundedBox(p - vec2(e, 0.0), halfExtent, radius),
        sdRoundedBox(p + vec2(0.0, e), halfExtent, radius) -
        sdRoundedBox(p - vec2(0.0, e), halfExtent, radius)
    );
    vec2 normal = normalize(grad + vec2(1e-6));

    // Depth into the glass: 0 at the rim, rising to 1 at the inner edge of the
    // rim band. Squared so the bend concentrates near the boundary the way a
    // real bevelled edge behaves, leaving the middle of the panel flat so text
    // behind it stays legible.
    float depth = clamp(-d / thickness, 0.0, 1.0);
    float bend  = (1.0 - depth) * (1.0 - depth);

    // Debug: paint the lens field itself. Confirms on-device that the shader is
    // running and that the panel rect matches the texture — a question no
    // amount of reading the docs settled definitively.
    if (uDebug > 0.5) {
        fragColor = vec4(bend, depth, 0.0, 1.0);
        return;
    }

    // Refract: walk the sample point along the inward normal, then frost the
    // displaced position. Order matters — frosting first and refracting after
    // would smear an already-blurred image and lose the bend entirely.
    vec2 offset = normal * bend * refract;
    vec4 refracted = frost(frag + offset, uBlur * dpr);

    // Specular rim: a fixed light from the upper-left catching the bevel. Not
    // motion-reactive — that needs sensor input the compositor does not expose.
    vec2  lightDir = normalize(vec2(-0.55, -0.83));
    float facing   = max(dot(normal, lightDir), 0.0);
    float rim      = pow(facing, 3.0) * bend * uSpecular;

    fragColor = refracted + vec4(vec3(rim), 0.0);
}
