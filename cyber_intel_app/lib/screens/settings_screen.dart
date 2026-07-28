import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../theme/app_theme.dart';

/// Detection Mode + connection settings.
///
/// The three tiers mirror ARCHITECTURE.md. Availability is not yet probed on
/// device, so anything beyond Standard is shown as unavailable rather than
/// offered — claiming a capability we cannot deliver would be worse than
/// showing none.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();

    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg,
          MediaQuery.of(context).padding.top + 74, AppSpacing.lg,
          AppSpacing.navBarClearance),
      children: [
        Text('DETECTION MODE', style: AppTheme.label()),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'How much of the device QuantX is allowed to inspect.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),

        _ModeTile(
          title: 'Standard',
          subtitle: 'Protects this app. No setup, no trade-off.',
          detail: 'App integrity · injection & hook detection · '
              'accessibility and overlay audit',
          icon: Icons.verified_user_outlined,
          available: true,
          selected: _mode == 0,
          onTap: () => setState(() => _mode = 0),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ModeTile(
          title: 'Deep Scan',
          subtitle: 'System-wide audit via Shizuku. Temporary session.',
          detail: 'Adds system logs · all-app permissions · network activity',
          warning: 'Requires Developer Options. QuantX reports that as a '
              'finding and asks you to turn it off afterwards.',
          icon: Icons.travel_explore_outlined,
          available: false,
          unavailableReason: 'Shizuku not detected',
          selected: _mode == 1,
          onTap: () {},
        ),
        const SizedBox(height: AppSpacing.sm),
        _ModeTile(
          title: 'Full',
          subtitle: 'Real-time kernel monitoring. Cross-app backdoors.',
          detail: 'Adds other-process injection · system partition integrity · '
              'boot persistence',
          warning: 'For already-rooted devices. QuantX will never ask you to '
              'root, and reports rooting as a finding.',
          icon: Icons.memory_outlined,
          available: false,
          unavailableReason: 'Root not detected',
          selected: _mode == 2,
          onTap: () {},
        ),

        const SizedBox(height: AppSpacing.xl),
        Text('PRIVACY', style: AppTheme.label()),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.green.withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.green.withOpacity(0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, color: AppColors.green, size: 18),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'Scanning runs entirely on this device. Only finding codes '
                  'are sent for advice — never app names, network names, file '
                  'paths or logs.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xl),
        Text('CONNECTION', style: AppTheme.label()),
        const SizedBox(height: AppSpacing.sm),
        _InfoRow(
          label: 'Assistant',
          value: api.isLoading ? 'Busy' : 'Ready',
          dot: api.isLoading ? AppColors.medium : AppColors.green,
        ),
        _InfoRow(label: 'Messages this session', value: '${api.queryCount}'),
        _InfoRow(label: 'History', value: 'Stored on device only'),

        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(
          onPressed: () => _confirmClear(context, api),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Clear conversation history'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.critical,
            minimumSize: const Size(0, 48),
            side: BorderSide(color: AppColors.critical.withOpacity(0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: Text('QuantX 1.1.0', style: AppTheme.mono(size: 11)),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, ApiService api) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title: const Text('Clear history?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: const Text(
          'This permanently deletes every message stored on this device.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear',
                style: TextStyle(color: AppColors.critical)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) api.clearChat(context);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ModeTile extends StatelessWidget {
  final String title, subtitle, detail;
  final String? warning, unavailableReason;
  final IconData icon;
  final bool available, selected;
  final VoidCallback onTap;

  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.icon,
    required this.available,
    required this.selected,
    required this.onTap,
    this.warning,
    this.unavailableReason,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected && available;
    return Opacity(
      opacity: available ? 1 : 0.55,
      child: InkWell(
        onTap: available ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: active
                ? AppColors.gold.withOpacity(0.07)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: active ? AppColors.gold.withOpacity(0.5) : AppColors.border,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon,
                      size: 18,
                      color: active ? AppColors.gold : AppColors.textMuted),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? AppColors.gold
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!available)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(unavailableReason ?? 'Unavailable',
                          style: AppTheme.mono(size: 10)),
                    )
                  else
                    Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: active ? AppColors.gold : AppColors.textMuted,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: AppSpacing.xs),
              Text(detail,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted, height: 1.45)),
              if (warning != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 13, color: AppColors.medium),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(warning!,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.medium,
                              height: 1.45)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final Color? dot;
  const _InfoRow({required this.label, required this.value, this.dot});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textSecondary)),
          ),
          if (dot != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(value,
              style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
