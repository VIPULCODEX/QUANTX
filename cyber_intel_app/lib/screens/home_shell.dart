import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback;
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

  /// Continuous finger position in slot units while a drag is live. Null when
  /// the indicator is under animation control instead.
  double? _drag;

  /// Smoothed horizontal speed in slots/frame, used to deform the capsule while
  /// it is being pulled. Smoothed because raw per-event deltas on a touch screen
  /// are noisy enough to make the stretch jitter visibly.
  double _vel = 0;

  /// Slot the finger was last over, so the haptic tick fires once per crossing
  /// rather than on every pointer move.
  int _lastTick = -1;

  bool get _dragging => _drag != null;

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
    if (old.index != widget.index && !_dragging) {
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

  /// Where the capsule is right now, from whichever source owns it.
  double get _pos => _drag ?? _positionAt(_slide.value);

  double _slotAt(double dx, double slotW, int count) =>
      (dx / slotW - 0.5).clamp(0.0, count - 1.0);

  void _grab(double dx, double slotW, int count) {
    _slide.stop();
    setState(() {
      _drag = _slotAt(dx, slotW, count);
      _vel = 0;
      _lastTick = _drag!.round();
    });
  }

  void _move(double dx, double slotW, int count) {
    final next = _slotAt(dx, slotW, count);
    setState(() {
      // Low-pass filter: 0.35 of the new delta, 0.65 of the running value.
      _vel = _vel * 0.65 + (next - (_drag ?? next)) * 0.35;
      _drag = next;
    });

    final over = next.round();
    if (over != _lastTick) {
      _lastTick = over;
      // Fires as the capsule crosses into a tab, not when the finger lifts —
      // the feedback should describe where the indicator is, not what will be
      // committed later.
      HapticFeedback.selectionClick();
    }
  }

  void _release(int count) {
    if (!_dragging) return;
    final landed = _drag!.round().clamp(0, count - 1);
    setState(() {
      _from = _drag!;
      _to = landed.toDouble();
      _drag = null;
      _vel = 0;
    });
    _slide.forward(from: 0);
    if (landed != widget.index) widget.onSelect(landed);
  }

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
                final pos = _pos;

                // Two sources of deformation, never both at once.
                //
                // Released: sin() over the flight, peaking mid-travel and
                // exactly zero at both ends, scaled by distance — so a settled
                // capsule is always its resting size.
                //
                // Held: the finger's own speed. This is the part that makes a
                // drag feel like pulling something viscous rather than
                // scrubbing a slider; the capsule lags into shape as you move
                // and relaxes the instant you stop, without you letting go.
                final double stretch = _dragging
                    ? (_vel.abs() * 9).clamp(0.0, 1.0)
                    : math.sin(_slide.value * math.pi) *
                        (_to - _from).abs().clamp(0.0, 1.6);

                final restW = slotW - 10;
                final pillW = restW + stretch * slotW * 0.34;
                // Held capsules sit a touch taller — the "picked up" cue. Small
                // on purpose: enough to feel, not enough to notice as a change
                // in size.
                final pillH = (h - 10) + (_dragging ? 2.0 : 0.0);

                return LiquidGlass(
                  borderRadius: BorderRadius.circular(22),
                  refract: 20,
                  thickness: 30,
                  specular: _dragging ? 0.28 : 0.20,
                  tintOpacity: 0.32,
                  lens: GlassLens(
                    center: Offset((pos + 0.5) * slotW, h / 2),
                    size: Size(pillW, pillH),
                    radius: pillH / 2,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // Tap and horizontal drag share one arena here rather than
                    // living on each tab. Per-tab detectors could not express a
                    // drag that crosses tabs — the gesture would be claimed by
                    // whichever child it started in and die at its boundary.
                    onTapUp: (d) {
                      final i = _slotAt(d.localPosition.dx, slotW, count)
                          .round()
                          .clamp(0, count - 1);
                      if (i != widget.index) widget.onSelect(i);
                    },
                    onHorizontalDragStart: (d) =>
                        _grab(d.localPosition.dx, slotW, count),
                    onHorizontalDragUpdate: (d) =>
                        _move(d.localPosition.dx, slotW, count),
                    onHorizontalDragEnd: (_) => _release(count),
                    onHorizontalDragCancel: () => _release(count),
                    // Press-and-hold, then drag: the long-press family keeps the
                    // gesture alive when the finger goes down and stays put,
                    // which the drag recognisers alone would never claim.
                    onLongPressStart: (d) =>
                        _grab(d.localPosition.dx, slotW, count),
                    onLongPressMoveUpdate: (d) =>
                        _move(d.localPosition.dx, slotW, count),
                    onLongPressEnd: (_) => _release(count),
                    onLongPressCancel: () => _release(count),
                    child: Stack(
                      children: [
                        // Visible capsule, positioned identically to the lens so
                        // the highlight and the refraction stay locked together.
                        Positioned(
                          left: (pos + 0.5) * slotW - pillW / 2,
                          top: (h - pillH) / 2,
                          width: pillW,
                          height: pillH,
                          child: _Indicator(held: _dragging),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
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
                                        // While dragging, highlight whatever the
                                        // capsule is over rather than the tab
                                        // that is still committed — the icon and
                                        // the glass must not disagree.
                                        selected: (_dragging
                                                ? pos.round()
                                                : widget.index) ==
                                            i,
                                        compact: !widget.expanded,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
  final bool held;
  const _Indicator({this.held = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: held
                ? [
                    AppColors.gold.withOpacity(0.30),
                    AppColors.gold.withOpacity(0.14),
                  ]
                : [
                    AppColors.gold.withOpacity(0.20),
                    AppColors.gold.withOpacity(0.09),
                  ],
          ),
          border: Border.all(
            color: AppColors.gold.withOpacity(held ? 0.48 : 0.30),
          ),
          // Only while held — a resting indicator with a glow reads as a
          // notification rather than as a control.
          boxShadow: held
              ? [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.22),
                    blurRadius: 14,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// Icon and label only.
///
/// Deliberately has no gesture handling and no background of its own. Both used
/// to live here: the pill was a per-tab AnimatedContainer cross-fading its
/// colour, so nothing ever travelled, and per-tab tap detectors made a drag
/// across tabs impossible — the gesture would be claimed by whichever child it
/// started in and die at that child's boundary. The bar owns both now.
class _Tab extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final bool selected, compact;

  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.gold : AppColors.textMuted;

    return Padding(
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
    );
  }
}
