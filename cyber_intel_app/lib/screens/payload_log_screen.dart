import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/leakage_service.dart';
import '../services/payload_log.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

/// "What was sent": the last requests QuantX made to its advice server,
/// exactly as transmitted, each with the most information it could carry.
class PayloadLogScreen extends StatefulWidget {
  const PayloadLogScreen({super.key});

  @override
  State<PayloadLogScreen> createState() => _PayloadLogScreenState();
}

class _PayloadLogScreenState extends State<PayloadLogScreen> {
  LeakageInfo? _leak;
  bool _leakTried = false;

  @override
  void initState() {
    super.initState();
    PayloadLog.instance.load();
    LeakageService.fetch().then((v) {
      if (!mounted) return;
      setState(() {
        _leak = v;
        _leakTried = true;
      });
    });
  }

  Future<void> _copyLog(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: PayloadLog.instance.exportJson()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Log copied. It contains codes, categories and '
            'timestamps only.')));
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _stamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What was sent')),
      body: AnimatedBuilder(
        animation: PayloadLog.instance,
        builder: (context, _) {
          final entries = PayloadLog.instance.entries;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const Text(
                'Each request below is shown exactly as it left this phone: '
                'finding codes and coarse categories only. No app names, '
                'network names, file paths or logs.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              _capacityNote(),
              const SizedBox(height: AppSpacing.lg),
              if (entries.isEmpty)
                const Text(
                  'Nothing has been sent yet. Run a scan on the Integrity tab.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              for (final e in entries) ...[
                _entryCard(e),
                const SizedBox(height: AppSpacing.md),
              ],
              if (entries.isNotEmpty)
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    TextButton.icon(
                      onPressed: () => _copyLog(context),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy log'),
                    ),
                    TextButton.icon(
                      onPressed: () => PayloadLog.instance.clear(),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear this log'),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _capacityNote() {
    final l = _leak;
    final String text;
    if (l != null) {
      text = 'The format allows ${l.totalPayloads} distinct messages, so one '
          'finding can carry at most ${l.payloadBitsMax.toStringAsFixed(1)} '
          'bits. This is a ceiling, not a measurement of your traffic.';
    } else if (_leakTried) {
      text = 'Bit estimates are unavailable while the server cannot be reached.';
    } else {
      text = 'Loading bit estimates…';
    }
    return Text(text,
        style: const TextStyle(
            color: AppColors.textMuted, fontSize: 11.5, height: 1.45));
  }

  Widget _entryCard(SentPayload e) {
    final findings = e.findings;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_stamp(e.time), style: AppTheme.mono(size: 11)),
          const SizedBox(height: AppSpacing.sm),
          if (findings.isEmpty)
            Text(e.body, style: AppTheme.mono(size: 11)),
          for (final f in findings) ...[
            SelectableText(jsonEncode(f), style: AppTheme.mono(size: 11.5)),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.sm),
              child: Text(_bitsLabel('${f['code']}'),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  String _bitsLabel(String code) {
    final l = _leak;
    if (l == null) return 'bits: n/a';
    final facet = l.facetBits[code];
    if (facet == null) return 'bits: n/a';
    return 'at most ${l.payloadBitsMax.toStringAsFixed(1)} bits '
        '(${facet.toStringAsFixed(1)} from categories)';
  }
}
