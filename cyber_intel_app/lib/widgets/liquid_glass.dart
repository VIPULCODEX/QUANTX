import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Loads the refraction shader once, and degrades safely if it is unavailable.
///
/// `ImageFilter.shader` requires Impeller. Impeller is the Android default from
/// Flutter 3.27 and this app targets 3.44, but a device or backend without it
/// would throw at filter-construction time. Rather than gamble, the program is
/// loaded once at startup and every consumer checks [ready] — when it is false
/// the UI falls back to the plain Gaussian blur, which is exactly what shipped
/// in v1.1.0. A shader problem can therefore cost the refraction effect, never
/// the navigation bar.
class LiquidGlassProgram {
  static ui.FragmentProgram? _program;
  static bool _tried = false;
  static String? _error;

  static bool get ready => _program != null;
  static String? get error => _error;

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
  /// in liquid_glass.frag. uSize occupies 0 and 1 because a vec2 consumes two
  /// float slots.
  static ui.FragmentShader? build({
    required Size size,
    required double radius,
    required double refract,
    required double thickness,
    required double specular,
  }) {
    final p = _program;
    if (p == null) return null;
    final s = p.fragmentShader();
    s.setFloat(0, size.width);
    s.setFloat(1, size.height);
    s.setFloat(2, radius);
    s.setFloat(3, refract);
    s.setFloat(4, thickness);
    s.setFloat(5, specular);
    return s;
  }
}

/// A glass panel that refracts the content painted behind it.
///
/// Falls back to [ImageFilter.blur] when the shader is unavailable, so callers
/// never need to branch.
///
/// PERFORMANCE: this is still a BackdropFilter — it forces a saveLayer and
/// re-filters its backdrop every frame. The same contract as GlassSurface
/// applies: at most two of these alive at once, never inside a scrolling list,
/// always clipped so the filter is bounded to its own rect rather than the
/// whole screen.
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

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.refract = 14,
    this.thickness = 28,
    this.specular = 0.16,
    this.blur = 8,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final base = tint ?? AppColors.surface;

    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          ui.ImageFilter filter;
          if (LiquidGlassProgram.ready && size.width > 0 && size.height > 0) {
            final shader = LiquidGlassProgram.build(
              size: size,
              radius: borderRadius.topLeft.x,
              refract: refract,
              thickness: thickness,
              specular: specular,
            );
            filter = shader != null
                ? ui.ImageFilter.compose(
                    // Blur first, then refract the blurred result: refracting
                    // sharp content produces visible edge artefacts.
                    outer: ui.ImageFilter.shader(shader),
                    inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  )
                : ui.ImageFilter.blur(sigmaX: blur + 12, sigmaY: blur + 12);
          } else {
            // v1.1.0 behaviour, unchanged.
            filter = ui.ImageFilter.blur(sigmaX: blur + 12, sigmaY: blur + 12);
          }

          return BackdropFilter(
            filter: filter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    base.withOpacity(0.55),
                    base.withOpacity(0.42),
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
