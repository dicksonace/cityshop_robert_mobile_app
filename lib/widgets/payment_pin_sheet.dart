import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_sheet.dart';

/// Prompts for the buyer's 4-digit payment PIN. Returns the PIN, or null if cancelled.
Future<String?> promptPaymentPin(
  BuildContext context, {
  String title = 'Enter payment PIN',
  String subtitle = 'Confirm with your 4-digit payment PIN',
}) {
  return showAppSheet<String>(
    context: context,
    builder: (ctx) => _PaymentPinPadSheet(title: title, subtitle: subtitle),
  );
}

class _PaymentPinPadSheet extends StatefulWidget {
  const _PaymentPinPadSheet({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  State<_PaymentPinPadSheet> createState() => _PaymentPinPadSheetState();
}

class _PaymentPinPadSheetState extends State<_PaymentPinPadSheet> {
  String pin = '';

    void _digit(String d) {
    if (pin.length >= 4) return;
    HapticFeedback.selectionClick();
    final next = '$pin$d';
    setState(() => pin = next);
    if (next.length == 4) {
      Future.microtask(() {
        if (mounted) Navigator.of(context).pop(next);
      });
    }
  }

  void _backspace() {
    if (pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => pin = pin.substring(0, pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      action: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      children: [
        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(widget.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final filled = i < pin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: filled ? AppColors.primary : const Color(0xFFD1D5DB),
                  width: 2,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '⌫'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: row.map((key) {
                if (key.isEmpty) return const Expanded(child: SizedBox());
                final isBack = key == '⌫';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Material(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => isBack ? _backspace() : _digit(key),
                        child: SizedBox(
                          height: 52,
                          child: Center(
                            child: isBack
                                ? const Icon(Icons.backspace_outlined, size: 22)
                                : Text(
                                    key,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
