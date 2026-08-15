import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Transfer to China — Alipay / WeChat Pay. Disabled until CN payouts go live.
class ChinaTransferChannels extends StatelessWidget {
  const ChinaTransferChannels({super.key, this.onUnavailable});

  final void Function(String channel)? onUnavailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose how to receive in China',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 4),
        const Text(
          'Send wallet funds to Alipay or WeChat Pay. Currently not available.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 12),
        _ChinaChannelTile(
          label: 'Alipay',
          mark: '支',
          color: const Color(0xFF1677FF),
          onTap: () => onUnavailable?.call('Alipay'),
        ),
        const SizedBox(height: 8),
        _ChinaChannelTile(
          label: 'WeChat Pay',
          mark: '微',
          color: const Color(0xFF07C160),
          onTap: () => onUnavailable?.call('WeChat Pay'),
        ),
      ],
    );
  }
}

class _ChinaChannelTile extends StatelessWidget {
  const _ChinaChannelTile({
    required this.label,
    required this.mark,
    required this.color,
    this.onTap,
  });

  final String label;
  final String mark;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  mark,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Currently not available',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
