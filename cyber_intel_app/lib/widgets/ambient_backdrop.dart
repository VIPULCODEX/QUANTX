import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The layer that makes the glass visible at all.
///
/// WHY THIS EXISTS — this is the part that was missing, and no amount of shader
/// work would have substituted for it.
///
/// Refraction does exactly one thing: it displaces the coordinate a fragment
/// samples the backdrop at. If the backdrop is a flat field, displacing the
/// sample point returns the same colour it would have returned anyway, and the
/// output is bit-for-bit identical to no refraction at all.
///
/// The app background was #0B0F14 with surfaces at #121820 — a spread of about
/// seven levels per channel across most of the screen. The shader was correct
/// and its output was invisible, because there was nothing behind the glass
/// worth bending. Rewriting the app in SwiftUI or Compose would have reproduced
/// the same non-effect for the same reason: this is a contrast problem, not a
/// framework problem.
///
/// So this paints two things behind everything else:
///
///   * low-frequency colour blooms, which give the panel interior a gradient to
///     shift, and
///   * a faint high-frequency grid, which is what actually sells the effect —
///     straight lines are the most legible possible evidence of a bend. A
///     gradient can distort a long way before the eye notices; a straight line
///     cannot move at all without being seen.
///
/// Cost is one static paint per size change: no blur, no saveLayer, no
/// per-frame work.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AmbientPainter(),
        isComplex: true,
        willChange: false,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  // Kept deliberately restrained. This is a security tool, not a lock screen —
  // the blooms should read as depth in the dark, never as decoration.
  static const _goldBloom = Color(0xFFC8A24A);
  static const _coolBloom = Color(0xFF3E7FA8);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = AppColors.bg);

    // Upper-left warm bloom — sits under the app bar, so the title area has a
    // luminance ramp for the top glass edge to bend.
    _bloom(canvas, size, const Alignment(-0.75, -0.85), 0.95, _goldBloom, 0.085);

    // Lower-right cool bloom — under the tab bar, where the rounded corners are
    // and therefore where refraction is strongest.
    _bloom(canvas, size, const Alignment(0.85, 0.80), 1.05, _coolBloom, 0.075);

    // A third, very faint, to stop the middle of the screen going dead flat.
    _bloom(canvas, size, const Alignment(0.10, 0.15), 0.85, _goldBloom, 0.030);

    _grid(canvas, size);
  }

  void _bloom(Canvas canvas, Size size, Alignment at, double scale, Color c,
      double opacity) {
    final centre = at.alongSize(size);
    final radius = size.shortestSide * scale;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [c.withOpacity(opacity), c.withOpacity(0.0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );
  }

  /// Faint technical grid. The single most useful thing on this layer: a
  /// straight line cannot be displaced without the eye catching it, so this is
  /// what turns "is that refracting?" into an unambiguous yes.
  void _grid(Canvas canvas, Size size) {
    const step = 30.0;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..strokeWidth = 1.0
      ..isAntiAlias = false;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Every fifth line slightly stronger, so displacement is readable at two
    // scales rather than one.
    final major = Paint()
      ..color = Colors.white.withOpacity(0.055)
      ..strokeWidth = 1.0
      ..isAntiAlias = false;

    for (double x = 0; x <= size.width; x += step * 5) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
    }
    for (double y = 0; y <= size.height; y += step * 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) => false;
}
