import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Renders the assistant's structured replies.
///
/// The backend prompts force a shape like:
///   Attack Type: ...
///   Explanation: ...
///   What to Do:
///   - step
///   Confidence: High
///
/// That was previously dumped into a single Text widget, so the structure the
/// prompt works hard to produce was invisible. This parses the common shapes —
/// `Label: value`, bullets, and `**bold**` — without pulling in a markdown
/// dependency for what is a small, known grammar.
class MessageBody extends StatelessWidget {
  final String text;
  const MessageBody({super.key, required this.text});

  static final _labelRe = RegExp(
    r'^(Attack Type|Explanation|What to Do|Confidence|Answer|Key Points|'
    r'Risk Level|Assessment|Action|Overall Security|Issues|Top Priority Fix|'
    r'Suspicious Apps Found|Flagged|Safe Apps|Recommendation|Summary|Impact|'
    r'Recent Cyber Incident|What this means|Do this now|Urgency)\s*:\s*(.*)$',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final lines = text.trim().split('\n');

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: AppSpacing.sm));
        continue;
      }

      final trimmed = line.trim();

      // Horizontal rule between news items
      if (trimmed == '---' || trimmed == '***') {
        blocks.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Divider(),
        ));
        continue;
      }

      // Bullet
      if (trimmed.startsWith('- ') || trimmed.startsWith('• ') ||
          trimmed.startsWith('* ')) {
        blocks.add(_bullet(trimmed.substring(2).trim()));
        continue;
      }

      // Numbered step
      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        blocks.add(_numbered(numbered.group(1)!, numbered.group(2)!));
        continue;
      }

      // Markdown heading (### 1. Potential Vulnerabilities)
      if (trimmed.startsWith('#')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
          child: Text(
            trimmed.replaceAll(RegExp(r'^#+\s*'), ''),
            style: AppTheme.label(color: AppColors.gold),
          ),
        ));
        continue;
      }

      // Label: value
      final m = _labelRe.firstMatch(trimmed);
      if (m != null) {
        blocks.add(_labelled(m.group(1)!, m.group(2)!.trim()));
        continue;
      }

      blocks.add(_paragraph(trimmed));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _labelled(String label, String value) {
    final accent = _accentFor(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTheme.label(color: AppColors.gold)),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 2),
            accent == null
                ? _paragraph(value)
                : Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: accent.withOpacity(0.4)),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
          ],
        ],
      ),
    );
  }

  /// Severity-style values get a coloured chip instead of plain text.
  Color? _accentFor(String value) {
    final v = value.trim().toUpperCase();
    const map = {
      'CRITICAL': AppColors.critical,
      'HIGH': AppColors.high,
      'AT RISK': AppColors.high,
      'MEDIUM': AppColors.medium,
      'LOW': AppColors.low,
      'SAFE': AppColors.safe,
      'SECURE': AppColors.safe,
      'IMMEDIATE': AppColors.critical,
      'SOON': AppColors.medium,
      'WHEN CONVENIENT': AppColors.low,
    };
    for (final e in map.entries) {
      if (v == e.key) return e.value;
    }
    return null;
  }

  Widget _bullet(String content) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7, right: 10),
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(child: _paragraph(content)),
          ],
        ),
      );

  Widget _numbered(String n, String content) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 10, top: 1),
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(n,
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(child: _paragraph(content)),
          ],
        ),
      );

  /// Paragraph with inline **bold** support.
  Widget _paragraph(String content) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    var i = 0;
    for (final m in re.allMatches(content)) {
      if (m.start > i) {
        spans.add(TextSpan(text: content.substring(i, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(
            fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ));
      i = m.end;
    }
    if (i < content.length) spans.add(TextSpan(text: content.substring(i)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
          children: spans.isEmpty ? [TextSpan(text: content)] : spans,
        ),
      ),
    );
  }
}
