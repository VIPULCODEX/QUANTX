import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/message_body.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  int _lastCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The previous chat list never scrolled, so replies arrived off-screen and
  /// the app looked unresponsive.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _send(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    context.read<ApiService>().sendMessage(q);
    _controller.clear();
    _focus.unfocus();
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ApiService>(
      builder: (context, api, _) {
        if (api.messages.length != _lastCount) {
          _lastCount = api.messages.length;
          _scrollToEnd();
        }

        return Column(
          children: [
            Expanded(
              child: api.messages.isEmpty
                  ? _EmptyState(onPick: _send)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                      itemCount: api.messages.length,
                      itemBuilder: (context, i) => _Bubble(msg: api.messages[i]),
                    ),
            ),
            if (api.isLoading) const _Thinking(),
            _Composer(
              controller: _controller,
              focus: _focus,
              enabled: !api.isLoading,
              onSend: () => _send(_controller.text),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final void Function(String) onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: const Icon(Icons.shield_outlined,
                color: AppColors.gold, size: 28),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'Ask about a threat',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Describe what happened, or ask a security question.\nAnswers are grounded in a local threat knowledge base.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('TRY ASKING', style: AppTheme.label(), textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.md),
        ..._ChatScreenSuggestions.items.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: InkWell(
              onTap: () => onPick(s),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 13.5, color: AppColors.textSecondary)),
                    ),
                    const Icon(Icons.arrow_outward,
                        size: 15, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatScreenSuggestions {
  static const items = [
    'I clicked a suspicious link — what now?',
    'How do I spot a phishing email?',
    'Is public Wi-Fi safe for banking?',
    'What is an accessibility service attack?',
  ];
}

// ─────────────────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final ApiMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md, left: 48),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.14),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.lg),
              topRight: Radius.circular(AppRadius.sm),
              bottomLeft: Radius.circular(AppRadius.lg),
              bottomRight: Radius.circular(AppRadius.lg),
            ),
            border: Border.all(color: AppColors.gold.withOpacity(0.28)),
          ),
          child: Text(
            msg.content,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14, height: 1.45),
          ),
        ),
      );
    }

    final isAlert = msg.type == 'alert';
    final accent = isAlert ? AppColors.critical : AppColors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md, right: 24),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: isAlert ? AppColors.critical.withOpacity(0.4) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAlert
                    ? Icons.warning_amber_rounded
                    : msg.type == 'news'
                        ? Icons.feed_outlined
                        : Icons.shield_outlined,
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                isAlert ? 'THREAT ANALYSIS' : 'QUANTX',
                style: AppTheme.label(color: accent),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MessageBody(text: msg.content),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.lg, bottom: AppSpacing.md, right: AppSpacing.lg),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.gold),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('Analysing…', style: AppTheme.label()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md + MediaQuery.of(context).viewPadding.bottom * 0.2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Describe a threat or ask a question…',
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 48,
            height: 48,
            child: Material(
              color: enabled
                  ? AppColors.gold
                  : AppColors.gold.withOpacity(0.3),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                onTap: enabled ? onSend : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: Color(0xFF1A1200), size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
