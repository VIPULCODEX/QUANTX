import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../security_dashboard.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_glass.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// Root navigation with frosted glass bars.
///
/// Two things make the glass actually read:
///   1. `extendBody` / `extendBodyBehindAppBar` let content scroll UNDER the
///      bars. Without that there is nothing behind them to blur and the effect
///      collapses into flat translucency.
///   2. Children reserve their own bottom padding via
///      [AppSpacing.navBarClearance], since the bars overlap the content area.
///
/// The tab bar also contracts as you scroll down and expands on the way back
/// up, which is the behaviour that gives the bar its sense of being a floating
/// material rather than a fixed chrome strip.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _navExpanded = true;

  static const _titles = ['Assistant', 'Security Scan', 'Settings'];
  static const _subtitles = [
    'Threat intelligence',
    'On-device analysis',
    'Detection & privacy',
  ];

  /// Collapse on downward scroll, expand on upward or at rest.
  bool _onScroll(ScrollNotification n) {
    if (n is UserScrollNotification) {
      final expand = switch (n.direction) {
        ScrollDirection.reverse => false,
        ScrollDirection.forward => true,
        ScrollDirection.idle => _navExpanded,
      };
      if (expand != _navExpanded) setState(() => _navExpanded = expand);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(58 + topInset),
        child: LiquidGlass(
          refract: 14,
          thickness: 34,
          specular: 0.12,
          tintOpacity: 0.40,
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              _titles[_index],
                              key: ValueKey(_index),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(_subtitles[_index],
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    const _StatusPill(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // The ambient layer is painted FIRST so both glass bars have something to
      // refract. Order is the whole point: a BackdropFilter samples what was
      // painted before it, so anything below this in the stack is invisible to
      // the shader.
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackdrop()),
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: IndexedStack(
              index: _index,
              children: const [
                ChatScreen(),
                SecurityDashboardScreen(embedded: true),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _GlassTabBar(
        index: _index,
        expanded: _navExpanded,
        bottomInset: bottomInset,
        onSelect: (i) => setState(() {
          _index = i;
          _navExpanded = true;
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.green.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.green.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: AppColors.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('PROTECTED', style: AppTheme.label(color: AppColors.green)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Floating glass tab bar that contracts on scroll.
///
/// Inset from the screen edges so the blur has visible content around it and
/// the corner radius reads as concentric with the device corners — a flush bar
/// loses both.
class _GlassTabBar extends StatefulWidget {
  final int index;
  final bool expanded;
  final double bottomInset;
  final ValueChanged<int> onSelect;

  const _GlassTabBar({
    required this.index,
    required this.expanded,
    required this.bottomInset,
    required this.onSelect,
  });

  static const items = [
    (Icons.forum_outlined, Icons.forum, 'Assistant'),
    (Icons.radar_outlined, Icons.radar, 'Scan'),
    (Icons.tune_outlined, Icons.tune, 'Settings'),
  ];

  @override
  State<_GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<_GlassTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.index.toDouble();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _GlassTabBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      // Retarget from wherever the indicator currently IS, not from the
      // previous tab. Tapping mid-flight otherwise makes it jump backwards
      // before setting off again.
      _from = _positionAt(_slide.value);
      _to = widget.index.toDouble();
      _slide.forward(from: 0);
    }
  }

  double _positionAt(double t) =>
      _from + (_to - _from) * Curves.easeOutCubic.transform(t.clamp(0, 1));

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _GlassTabBar.items.length;

    return Padding(
      // FULL bottom inset, not a fraction of it. Scaling it down put the bar
      // underneath the system navigation bar on 3-button-nav devices.
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, widget.bottomInset + AppSpacing.sm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: widget.expanded ? 62 : 50,
        child: LayoutBuilder(
          builder: (context, c) {
            final slotW = c.maxWidth / count;
            final h = c.maxHeight;

            return AnimatedBuilder(
              animation: _slide,
              builder: (context, child) {
                final pos = _positionAt(_slide.value);
                final travel = (_to - _from).abs();

                // The liquid part. A capsule that merely translates reads as a
                // sliding rectangle; one that stretches along its direction of
                // travel and settles back reads as a droplet being pulled.
                // sin() peaks at mid-flight and returns to zero at both ends,
                // so the indicator is always its resting size when stationary.
                final stretch =
                    math.sin(_slide.value * math.pi) * travel.clamp(0.0, 1.6);

                final restW = slotW - 10;
                final pillW = restW + stretch * slotW * 0.34;
                final pillH = h - 10;

                return LiquidGlass(
                  borderRadius: BorderRadius.circular(22),
                  refract: 20,
                  thickness: 30,
                  specular: 0.20,
                  tintOpacity: 0.32,
                  lens: GlassLens(
                    center: Offset((pos + 0.5) * slotW, h / 2),
                    size: Size(pillW, pillH),
                    radius: pillH / 2,
                  ),
                  child: Stack(
                    children: [
                      // Visible capsule, positioned identically to the lens so
                      // the highlight and the refraction stay locked together.
                      Positioned(
                        left: (pos + 0.5) * slotW - pillW / 2,
                        top: 5,
                        width: pillW,
                        height: pillH,
                        child: const _Indicator(),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.07)),
                          ),
                          child: Row(
                            children: [
                              for (var i = 0; i < count; i++)
                                Expanded(
                                  child: _Tab(
                                    icon: _GlassTabBar.items[i].$1,
                                    activeIcon: _GlassTabBar.items[i].$2,
                                    label: _GlassTabBar.items[i].$3,
                                    selected: widget.index == i,
                                    compact: !widget.expanded,
                                    onTap: () => widget.onSelect(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The travelling capsule's visible body.
///
/// Deliberately thin: the shader supplies the refraction and the specular rim,
/// so this only needs to add the tint and a hairline edge. Painting a strong
/// fill here would hide the lensing underneath it.
class _Indicator extends StatelessWidget {
  const _Indicator();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.gold.withOpacity(0.20),
              AppColors.gold.withOpacity(0.09),
            ],
          ),
          border: Border.all(color: AppColors.gold.withOpacity(0.30)),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final bool selected, compact;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.gold : AppColors.textMuted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // No background here any more. The selected pill used to be a per-tab
      // AnimatedContainer that cross-faded its colour — the old one fading out
      // while the new one faded in — so nothing ever travelled. A single
      // indicator now slides in _GlassTabBarState.
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, size: compact ? 19 : 20, color: color),
            // Labels fade out as the bar contracts rather than popping away.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: compact
                  ? const SizedBox(width: 1)
                  : Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: color,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
