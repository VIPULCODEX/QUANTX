import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Frosted-glass surfaces, in the spirit of iOS Liquid Glass.
///
/// What this is: a real backdrop blur — it samples and blurs whatever is
/// actually painted behind it — plus a layered tint and a specular rim.
///
/// What this is NOT: Apple's Liquid Glass. That does true optical refraction
/// and motion-reactive speculars, rendered by the OS compositor with access to
/// the wallpaper behind the window. An Android app cannot reach that.
///
/// PERFORMANCE CONTRACT — read before reusing this widget.
/// Every BackdropFilter forces a saveLayer and re-blurs its backdrop each
/// frame. It is the most common source of Flutter jank on mid-range Android.
/// So:
///   * At most TWO of these are alive at once (app bar + tab bar).
///   * NEVER place one inside a scrolling list. Use [GlassCard] there — it is
///     an opaque look-alike with no blur.
///   * The BackdropFilter is always wrapped in a clip. An unclipped one blurs
///     the entire screen, not just its own bounds.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final BorderRadius? borderRadius;

  /// Which edge carries the bright specular line. Nav bars catch light on top,
  /// docked bars on the edge facing the content.
  final bool rimTop;
  final bool rimBottom;
  final Color? tint;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 22,
    this.borderRadius,
    this.rimTop = false,
    this.rimBottom = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final baseTint = tint ?? AppColors.surface;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          // Vertical tint ramp: glass reads as a solid pane of material rather
          // than flat translucency, which is what makes it feel like a surface.
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                baseTint.withOpacity(0.82),
                baseTint.withOpacity(0.68),
              ],
            ),
          ),
          child: Stack(
            children: [
              child,
              if (rimTop)
                const Positioned(top: 0, left: 0, right: 0, child: _Rim()),
              if (rimBottom)
                const Positioned(bottom: 0, left: 0, right: 0, child: _Rim()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hairline specular highlight. Brightest at centre, fading at the edges —
/// that falloff is what separates a light catch from a plain divider.
class _Rim extends StatelessWidget {
  const _Rim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.0),
              Colors.white.withOpacity(0.16),
              Colors.white.withOpacity(0.05),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Opaque card in the glass visual language.
///
/// Deliberately blur-free so it is safe inside lists. Reads as glass through
/// the same tint ramp, rim and radius, without the per-frame cost.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? accent;
  final bool selected;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accent,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent ?? AppColors.gold;
    final card = Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? [a.withOpacity(0.13), a.withOpacity(0.05)]
              : [
                  AppColors.surfaceRaised.withOpacity(0.9),
                  AppColors.surface.withOpacity(0.75),
                ],
        ),
        border: Border.all(
          color: selected ? a.withOpacity(0.45) : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Stack(
        children: [
          child,
          const Positioned(top: 0, left: 12, right: 12, child: _Rim()),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: card,
      ),
    );
  }
}

/// iOS-style grouped list section: a rounded container with hairline-separated
/// rows and a small caps caption above.
class GlassSection extends StatelessWidget {
  final String? caption;
  final List<Widget> children;

  const GlassSection({super.key, this.caption, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Padding(
          padding: EdgeInsets.only(left: AppSpacing.lg),
          child: Divider(height: 1),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpacing.xs, bottom: AppSpacing.sm),
            child: Text(caption!.toUpperCase(), style: AppTheme.label()),
          ),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.85),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}

/// Single row inside a [GlassSection] — iOS Settings geometry: leading glyph
/// in a tinted rounded square, title/subtitle stack, trailing accessory.
class GlassRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const GlassRow({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? AppColors.gold;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 16, color: c),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              height: 1.35)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ] else if (onTap != null)
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
