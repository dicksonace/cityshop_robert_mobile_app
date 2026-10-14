import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum PaymentOptionKind { flutterwave, korapay, junipay, paystack, manual, balance }

/// Shared payment row used on recharge, scan to pay, and checkout.
class PaymentOptionTile extends StatelessWidget {
  const PaymentOptionTile({
    super.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final PaymentOptionKind kind;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(kind, enabled);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? colors.icon : colors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.icon,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(colors.iconData, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: enabled ? const Color(0xFF111111) : const Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: enabled ? AppColors.textSecondary : const Color(0xFFB0B0B0),
                        ),
                      ),
                    ],
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

class _OptionColors {
  const _OptionColors({
    required this.background,
    required this.border,
    required this.icon,
    required this.iconData,
  });

  final Color background;
  final Color border;
  final Color icon;
  final IconData iconData;
}

_OptionColors _colors(PaymentOptionKind kind, bool enabled) {
  if (!enabled) {
    return const _OptionColors(
      background: Color(0xFFF9FAFB),
      border: Color(0xFFE5E7EB),
      icon: Color(0xFFD1D5DB),
      iconData: Icons.account_balance_wallet_outlined,
    );
  }
  switch (kind) {
    case PaymentOptionKind.flutterwave:
      return const _OptionColors(
        background: Color(0xFFEEF2FF),
        border: Color(0xFFA5B4FC),
        icon: Color(0xFF4F46E5),
        iconData: Icons.payments_outlined,
      );
    case PaymentOptionKind.korapay:
      return const _OptionColors(
        background: Color(0xFFECFDF5),
        border: Color(0xFF6EE7B7),
        icon: Color(0xFF059669),
        iconData: Icons.phone_android_rounded,
      );
    case PaymentOptionKind.junipay:
      return const _OptionColors(
        background: Color(0xFFFEF2F2),
        border: Color(0xFFFCA5A5),
        icon: Color(0xFFDC2626),
        iconData: Icons.phone_iphone_rounded,
      );
    case PaymentOptionKind.paystack:
      return const _OptionColors(
        background: Color(0xFFFFF7ED),
        border: Color(0xFFFDBA74),
        icon: AppColors.primary,
        iconData: Icons.smartphone,
      );
    case PaymentOptionKind.manual:
      return const _OptionColors(
        background: Colors.white,
        border: Color(0xFFBAE6FD),
        icon: Color(0xFF0EA5E9),
        iconData: Icons.upload_rounded,
      );
    case PaymentOptionKind.balance:
      return const _OptionColors(
        background: Color(0xFFFFF7ED),
        border: Color(0xFFFDBA74),
        icon: AppColors.primary,
        iconData: Icons.account_balance_wallet_outlined,
      );
  }
}

String paymentGatewayLabel(String gateway) {
  switch (gateway) {
    case 'flutterwave':
      return 'Flutterwave';
    case 'korapay':
      return 'Korapay';
    case 'junipay':
      return 'Junipay';
    default:
      return 'Paystack';
  }
}
