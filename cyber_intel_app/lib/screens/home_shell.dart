import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../security_dashboard.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
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
        child: GlassSurface(
          rimBottom: true,
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
      body: NotificationListener<ScrollNotification>(
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
class _GlassTabBar extends StatelessWidget {
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

  static const _items = [
    (Icons.forum_outlined, Icons.forum, 'Assistant'),
    (Icons.radar_outlined, Icons.radar, 'Scan'),
    (Icons.tune_outlined, Icons.tune, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      // FULL bottom inset, not a fraction of it. Scaling it down put the bar
      // underneath the system navigation bar on 3-button-nav devices.
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, bottomInset + AppSpacing.sm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: expanded ? 62 : 50,
        child: GlassSurface(
          blur: 26,
          rimTop: true,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _Tab(
                      icon: _items[i].$1,
                      activeIcon: _items[i].$2,
                      label: _items[i].$3,
                      selected: index == i,
                      compact: !expanded,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          // Selected pill sits inside the glass, echoing the iOS tab indicator.
          color: selected ? AppColors.gold.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
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
