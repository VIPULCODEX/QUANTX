import 'package:flutter/material.dart';
import '../theme/app_theme.dart';


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
