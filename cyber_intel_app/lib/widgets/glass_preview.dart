import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'liquid_glass.dart';

/// A small, self-contained demonstration of the glass: drag the pane around and
/// watch the pattern bend under it.
///
/// This replaces the "Show lens field" switch, which painted the real
/// navigation bars in false colour. That was a debugging tool built for one
/// specific question — is the panel geometry correct — and once that question
/// was answered it had no remaining use, while still being the strangest thing
/// in Settings.
///
/// The demonstration is the better diagnostic anyway. False colour required
/// knowing how to read it; here, if the rings do not visibly distort under the
/// pane, the effect is not working. No legend needed.
///
/// PERFORMANCE: this is a BackdropFilter inside a scrolling list, which is the
/// one placement the LiquidGlass docs warn against — it re-filters its backdrop
/// every frame, including every frame of a scroll. Accepted here because the
/// filtered rect is small and fixed, and it is wrapped in a RepaintBoundary so
/// it does not drag the rest of the list into its repaints. It stays a single
/// tile on one screen; do not copy the pattern into a list that repeats.
class GlassPreview extends StatefulWidget {
  const GlassPreview({super.key});

  @override
  State<GlassPreview> createState() => _GlassPreviewState();
}

class _GlassPreviewState extends State<GlassPreview> {
  static const double _h = 172;
  static const Size _pane = Size(132, 82);

  // Fractional position of the pane's centre within the tile, so it survives
  // width changes on rotation without drifting off the edge.
  Offset _at = const Offset(0.34, 0.5);

  void _moveTo(Offset local, Size box) {
    final halfW = _pane.width / 2 + 6;
    final halfH = _pane.height / 2 + 6;
    setState(() {
      _at = Offset(
        (local.dx / box.width)
            .clamp(halfW / box.width, 1 - halfW / box.width),
        (local.dy / box.height)
            .clamp(halfH / box.height, 1 - halfH / box.height),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          height: _h,
          child: LayoutBuilder(
            builder: (context, c) {
              final box = Size(c.maxWidth, _h);
              final centre = Offset(_at.dx * box.width, _at.dy * box.height);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _moveTo(d.localPosition, box),
                onPanUpdate: (d) => _moveTo(d.localPosition, box),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _LensTargetPainter()),
                    ),
                    Positioned(
                      left: centre.dx - _pane.width / 2,
                      top: centre.dy - _pane.height / 2,
                      width: _pane.width,
                      height: _pane.height,
                      child: const LiquidGlass(
                        borderRadius:
                            BorderRadius.all(Radius.circular(20)),
                        refract: 22,
                        thickness: 26,
                        specular: 0.26,
                        tintOpacity: 0.16,
                        child: SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: Text(
                        'DRAG THE PANE',
                        style: AppTheme.label(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Concentric rings on a tinted ground.
///
/// Rings rather than a grid: a straight line only shows displacement along one
/// axis, while a circle passing under a lens deforms visibly in every
/// direction at once, which is what makes a refracting edge unmistakable.
class _LensTargetPainter extends CustomPainter {
  static const _gold = Color(0xFFC8A24A);
  static const _cool = Color(0xFF3E7FA8);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.bg);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33C8A24A), Color(0x00000000), Color(0x333E7FA8)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    final centre = Offset(size.width * 0.5, size.height * 0.5);
    final maxR = size.longestSide * 0.8;

    for (double r = 9; r < maxR; r += 13) {
      final t = (r / maxR).clamp(0.0, 1.0);
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = Color.lerp(_gold, _cool, t)!.withOpacity(0.34 * (1 - t) + 0.10),
      );
    }

    // A pair of axes gives the eye a straight reference to judge the ring
    // distortion against.
    final axis = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centre.dy), Offset(size.width, centre.dy), axis);
    canvas.drawLine(Offset(centre.dx, 0), Offset(centre.dx, size.height), axis);
  }

  @override
  bool shouldRepaint(covariant _LensTargetPainter oldDelegate) => false;
}
