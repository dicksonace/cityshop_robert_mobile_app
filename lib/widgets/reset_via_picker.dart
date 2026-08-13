import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Email vs SMS choice for password / PIN reset codes.
class ResetViaPicker extends StatelessWidget {
  const ResetViaPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.smsEnabled = true,
    this.emailEnabled = true,
  });

  final String value; // email | sms
  final ValueChanged<String> onChanged;
  final bool smsEnabled;
  final bool emailEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Send code via',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ViaChip(
                label: 'Email',
                icon: Icons.email_outlined,
                selected: value == 'email',
                enabled: emailEnabled,
                onTap: emailEnabled ? () => onChanged('email') : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ViaChip(
                label: 'SMS',
                icon: Icons.sms_outlined,
                selected: value == 'sms',
                enabled: smsEnabled,
                onTap: smsEnabled ? () => onChanged('sms') : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ViaChip extends StatelessWidget {
  const _ViaChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textMuted
        : selected
            ? AppColors.primary
            : AppColors.textSecondary;

    return Material(
      color: selected ? AppColors.ringOrange : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
