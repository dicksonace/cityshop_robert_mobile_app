import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// Inline insufficient-balance banner for withdrawal amount entry.
String? withdrawalBalanceMessage({
  required double amount,
  required double fee,
  required double available,
}) {
  if (amount <= 0) return null;
  final total = amount + fee;
  if (total <= available + 1e-9) return null;

  return 'Insufficient balance. Available: ${_money.format(available)}';
}

class WithdrawalBalanceAlert extends StatelessWidget {
  const WithdrawalBalanceAlert({
    super.key,
    required this.amount,
    required this.fee,
    required this.available,
  });

  final double amount;
  final double fee;
  final double available;

  @override
  Widget build(BuildContext context) {
    final message = withdrawalBalanceMessage(
      amount: amount,
      fee: fee,
      available: available,
    );
    if (message == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFDC2626),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
