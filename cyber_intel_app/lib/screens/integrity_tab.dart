import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/message_body.dart';

/// Tier 0 scan results.
///
/// Replaces the old Device tab, whose switches asked the user to declare their
/// own settings. A declared setting cannot be trusted in a security audit, and
/// every value it collected is now measured directly instead.
class IntegrityTab extends StatefulWidget {
  const IntegrityTab({super.key});

  @override
  State<IntegrityTab> createState() => _IntegrityTabState();
}

class _IntegrityTabState extends State<IntegrityTab> {
  @override
  void initState() {
    super.initState();
    // Scan on first open so the tab is never an empty prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<ScanService>();
      if (s.lastScan == null && !s.scanning) s.run();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scan = context.watch<ScanService>();

    return RefreshIndicator(
      onRefresh: scan.run,
      backgroundColor: AppColors.surface,
      color: AppColors.gold,
      child: ListView(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg,
            AppSpacing.lg, AppSpacing.bottomClearance(context)),
        children: [
          _Verdict(scan: scan),
          const SizedBox(height: AppSpacing.lg),

          if (scan.error != null)
            GlassCard(
              accent: AppColors.critical,
              child: Text('Scan error: ${scan.error}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            )
          else if (scan.findings.isEmpty && !scan.scanning) ...[
            GlassCard(
              accent: AppColors.safe,
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined,
                      color: AppColors.safe, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('No issues detected',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5)),
                        SizedBox(height: 3),
                        Text(
                          'No injection, debugger, tampering or untrusted '
                          'accessibility access found.',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12.5,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else
            ...scan.findings.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _FindingCard(finding: f),
                )),

          const SizedBox(height: AppSpacing.lg),
          const _WhatIsChecked(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Verdict extends StatelessWidget {
  final ScanService scan;
  const _Verdict({required this.scan});

  @override
  Widget build(BuildContext context) {
    final sev = scan.worstSeverity;
    final clear = sev == 'clear';
    final color = clear ? AppColors.safe : AppColors.severity(sev);
    final label = scan.scanning
        ? 'SCANNING'
        : clear
            ? 'PROTECTED'
            : sev.toUpperCase();

    return GlassCard(
      accent: color,
      selected: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: scan.scanning
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: AppColors.gold))
                    : Icon(clear ? Icons.shield : Icons.gpp_maybe,
                        color: color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(
                      scan.scanning
                          ? 'Checking this app and device posture…'
                          : '${scan.findings.length} finding'
                              '${scan.findings.length == 1 ? '' : 's'}'
                              '${scan.lastScan != null ? ' · ${_ago(scan.lastScan!)}' : ''}',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!scan.scanning)
                IconButton(
                  onPressed: scan.run,
                  icon: const Icon(Icons.refresh, color: AppColors.textMuted),
                  tooltip: 'Rescan',
                ),
            ],
          ),
          if (scan.adviceOffline) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Icon(Icons.cloud_off,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Server unreachable — showing built-in guidance. Detection '
                    'itself runs entirely on this device and is unaffected.',
                    style: AppTheme.mono(size: 10),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FindingCard extends StatefulWidget {
  final Finding finding;
  const _FindingCard({required this.finding});

  @override
  State<_FindingCard> createState() => _FindingCardState();
}

class _FindingCardState extends State<_FindingCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.finding;
    final color = AppColors.severity(f.severity);
    final steps =
        (f.offline?['steps'] as List?)?.cast<String>() ?? const <String>[];

    return GlassCard(
      accent: color,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.title ?? f.code,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                height: 1.3)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.16),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(f.severity.toUpperCase(),
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6)),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(f.code,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.mono(size: 10)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textMuted, size: 20),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (f.offline?['why'] != null) ...[
                    Text('WHY THIS MATTERS', style: AppTheme.label()),
                    const SizedBox(height: AppSpacing.xs),
                    Text('${f.offline!['why']}',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.5)),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (steps.isNotEmpty) ...[
                    Text('WHAT TO DO', style: AppTheme.label()),
                    const SizedBox(height: AppSpacing.sm),
                    ...steps.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                alignment: Alignment.center,
                                margin: const EdgeInsets.only(right: 9, top: 1),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Text('${e.key + 1}',
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                              Expanded(
                                child: Text(e.value,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        height: 1.45)),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (f.evidence.isNotEmpty) ...[
                    Row(
                      children: [
                        Text('EVIDENCE', style: AppTheme.label()),
                        const SizedBox(width: 6),
                        const Icon(Icons.phone_android,
                            size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text('stays on device', style: AppTheme.mono(size: 9)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.bg.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: SelectableText(
                        f.evidence.join('\n'),
                        style: AppTheme.mono(size: 11),
                      ),
                    ),
                  ],
                  if (f.ai != null && f.ai!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text('AI GUIDANCE', style: AppTheme.label()),
                    const SizedBox(height: AppSpacing.xs),
                    MessageBody(text: f.ai!),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _WhatIsChecked extends StatelessWidget {
  const _WhatIsChecked();

  static const _checks = [
    ('Instrumentation hooks', 'Frida, Xposed, LSPosed injected into this app'),
    ('Debugger attachment', 'JDWP and ptrace TracerPid'),
    ('Build signature', 'Repackaging and debug-key signing'),
    ('Accessibility access', 'Untrusted apps that can read your screen'),
    ('Notification access', 'Untrusted apps that can read OTP codes'),
    ('Developer surface', 'Developer options and USB debugging'),
    ('Root & emulator', 'su binaries, Magisk, emulator fingerprints'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WHAT IS CHECKED', style: AppTheme.label()),
        const SizedBox(height: AppSpacing.sm),
        GlassSection(
          children: _checks
              .map((c) => GlassRow(
                    icon: Icons.check_circle_outline,
                    iconColor: AppColors.safe,
                    title: c.$1,
                    subtitle: c.$2,
                  ))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.6),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'These checks raise the cost of an attack; they do not stop a '
                  'determined one. A hooking framework can interfere with the '
                  'code that detects it. Detection is strongest against '
                  'commodity malware, which is most of what reaches real users.',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
