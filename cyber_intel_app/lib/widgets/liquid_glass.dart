import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Loads the refraction shader once, and degrades safely if it is unavailable.
///
/// `ImageFilter.shader` requires Impeller. Impeller is the Android default from
/// Flutter 3.27 and this app targets 3.44, but a device or backend without it
/// would throw at filter-construction time. Rather than gamble, the program is
/// loaded once at startup and every consumer checks [ready] — when it is false
/// the UI falls back to a plain Gaussian blur, which is exactly what shipped in
/// v1.1.0. A shader problem can therefore cost the refraction effect, never the
/// navigation bar.
class LiquidGlassProgram {
  static ui.FragmentProgram? _program;
  static bool _tried = false;
  static String? _error;

  /// Renders the lens field as false colour instead of refracting, so the
  /// geometry the shader actually sees can be confirmed on a real device.
  /// Toggled from Settings; never on by default.
  static final ValueNotifier<bool> debug = ValueNotifier(false);

  static bool get ready => _program != null;
  static String? get error => _error;

  /// Set when ImageFilter.shader itself is rejected at runtime — which is a
  /// different failure from the program not loading, and the one that indicates
  /// a Skia backend rather than a bad shader.
  static bool _filterRejected = false;

  static void noteFilterFailure(Object e) {
    if (_filterRejected) return;
    _filterRejected = true;
    _error = 'ImageFilter.shader rejected (Impeller unavailable?): $e';
  }

  /// Human-readable state for the Settings diagnostics row.
  static String get status {
    if (_filterRejected) return 'Fallback — no Impeller';
    if (_program != null) return debug.value ? 'Active (debug view)' : 'Active';
    if (!_tried) return 'Not loaded';
    return 'Fallback — shader failed to load';
  }

  static Future<void> load() async {
    if (_tried) return;
    _tried = true;
    try {
      _program =
          await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    } catch (e) {
      _error = '$e';
      _program = null;
    }
  }

  /// Build a configured shader instance.
  ///
  /// Float indices are positional and must match the uniform declaration order
  /// in liquid_glass.frag. Indices 0 and 1 belong to `uSize`, which the ENGINE
  /// populates with the bound texture size — writing them from here is what
  /// silently disabled the whole effect in v1.4.0, so the first index this
  /// method may touch is 2.
  ///
  /// Every length below is in LOGICAL pixels; [dpr] lets the shader convert
  /// them into the device-pixel space its distance field works in.
  static ui.FragmentShader? build({
    required double radius,
    required double refract,
    required double thickness,
    required double specular,
    required double dpr,
    required double blur,
    GlassLens? lens,
  }) {
    final p = _program;
    if (p == null) return null;
    final s = p.fragmentShader();
    s.setFloat(2, radius);
    s.setFloat(3, refract);
    s.setFloat(4, thickness);
    s.setFloat(5, specular);
    s.setFloat(6, dpr);
    s.setFloat(7, debug.value ? 1.0 : 0.0);
    s.setFloat(8, blur);
    s.setFloat(9, lens?.center.dx ?? 0);
    s.setFloat(10, lens?.center.dy ?? 0);
    s.setFloat(11, (lens?.size.width ?? 0) / 2);
    s.setFloat(12, (lens?.size.height ?? 0) / 2);
    s.setFloat(13, lens?.radius ?? 0);
    s.setFloat(14, lens == null ? 0.0 : 1.0);
    return s;
  }
}

/// A second lens travelling inside a [LiquidGlass] panel — the selected-tab
/// indicator.
///
/// Coordinates are logical pixels relative to the panel's own top-left, which
/// is what a LayoutBuilder inside the panel measures. The shader converts to
/// device pixels itself.
class GlassLens {
  final Offset center;
  final Size size;
  final double radius;

  const GlassLens({
    required this.center,
    required this.size,
    required this.radius,
  });

  @override
  bool operator ==(Object other) =>
      other is GlassLens &&
      other.center == center &&
      other.size == size &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(center, size, radius);
}

/// A glass panel that refracts the content painted behind it.
///
/// Falls back to [ImageFilter.blur] when the shader is unavailable, so callers
/// never need to branch.
///
/// PERFORMANCE: this is a BackdropFilter — it forces a saveLayer and re-filters
/// its backdrop every frame. At most two of these alive at once, never inside a
/// scrolling list, always clipped so the filter is bounded to its own rect
/// rather than the whole screen. The clip is not only a performance measure:
/// the shader assumes the bound texture *is* the panel, which only holds while
/// the BackdropFilter is bounded.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// Peak edge displacement in logical pixels. Above roughly 24 the distortion
  /// stops reading as glass and starts reading as a rendering fault.
  final double refract;

  /// Width of the refracting rim. The panel interior stays undistorted so text
  /// behind it remains legible.
  final double thickness;

  final double specular;
  final double blur;
  final Color? tint;

  /// Optional travelling lens drawn inside this panel. Costs two extra SDF
  /// evaluations per fragment — no additional layer, no second saveLayer.
  final GlassLens? lens;

  /// Opacity of the tint wash. Low enough that the refracted backdrop stays
  /// visible through it — an opaque panel would hide the very effect it exists
  /// to show — but high enough to keep labels legible over busy content.
  final double tintOpacity;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.refract = 14,
    this.thickness = 28,
    this.specular = 0.16,
    this.blur = 8,
    this.tint,
    this.tintOpacity = 0.34,
    this.lens,
  });

  @override
  Widget build(BuildContext context) {
    final base = tint ?? AppColors.surface;
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return ClipRRect(
      borderRadius: borderRadius,
      child: ValueListenableBuilder<bool>(
        valueListenable: LiquidGlassProgram.debug,
        builder: (context, debugOn, _) {
          ui.ImageFilter filter;
          final shader = LiquidGlassProgram.ready
              ? LiquidGlassProgram.build(
                  radius: borderRadius.topLeft.x,
                  refract: refract,
                  thickness: thickness,
                  specular: specular,
                  dpr: dpr,
                  blur: blur,
                  lens: lens,
                )
              : null;

          // No compose(). Layering an ImageFilter.blur under the shader expands
          // the filtered coverage, so the texture the shader receives no longer
          // matches the panel rect its distance field assumes (flutter#170820).
          // The frost is done inside the shader instead.
          //
          // The try/catch is not defensive padding. FragmentProgram.fromAsset
          // succeeds on BOTH backends, so `ready` proves only that the program
          // loaded — ImageFilter.shader itself throws UnsupportedError on Skia.
          // Without this, a device that fell back to Skia would not lose the
          // effect, it would crash on every frame that drew a navigation bar.
          try {
            filter = shader != null
                ? ui.ImageFilter.shader(shader)
                : ui.ImageFilter.blur(sigmaX: blur + 12, sigmaY: blur + 12);
          } catch (e) {
            LiquidGlassProgram.noteFilterFailure(e);
            filter = ui.ImageFilter.blur(sigmaX: blur + 12, sigmaY: blur + 12);
          }

          return BackdropFilter(
            filter: filter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                // In debug view the tint is dropped entirely — the point is to
                // read the raw field, not to look good.
                gradient: debugOn
                    ? null
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          base.withOpacity(tintOpacity),
                          base.withOpacity(tintOpacity * 0.72),
                        ],
                      ),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
