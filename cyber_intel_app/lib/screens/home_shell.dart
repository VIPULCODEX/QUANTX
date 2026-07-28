import 'package:flutter/material.dart';
import '../security_dashboard.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// Root navigation.
///
/// Replaces the previous Drawer. A drawer hides the app's two primary actions
/// behind a hamburger; with only three destinations, a bottom bar keeps both
/// one tap away and matches what people expect from a mobile security app.
/// IndexedStack preserves each tab's scroll position and state across switches.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Assistant', 'Security Scan', 'Settings'];
  static const _subtitles = [
    'Threat intelligence',
    'On-device analysis',
    'Detection & privacy',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_titles[_index]),
            Text(_subtitles[_index],
                style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.1),
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
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          ChatScreen(),
          SecurityDashboardScreen(embedded: true),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
