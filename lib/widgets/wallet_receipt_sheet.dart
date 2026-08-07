import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'app_sheet.dart';

final _money = NumberFormat.currency(locale: 'en_GH', symbol: 'GH₵', decimalDigits: 2);
final _stamp = DateFormat('d MMM yyyy, h:mm a');

Future<void> showWalletReceiptSheet(
  BuildContext context, {
  required WalletTransactionItem tx,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => WalletReceiptSheet(tx: tx),
  );
}

class WalletReceiptSheet extends StatelessWidget {
  const WalletReceiptSheet({super.key, required this.tx});

  final WalletTransactionItem tx;

  String get _when {
    final raw = tx.createdAt;
    if (raw == null || raw.isEmpty) return '—';
    try {
      return _stamp.format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final credit = tx.isCredit;
    final amountColor = credit ? const Color(0xFF16A34A) : AppColors.danger;

    return SheetShell(
      action: FilledButton(
        onPressed: () => Navigator.pop(context),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Close'),
      ),
      children: [
        const Text(
          'Transaction receipt',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: credit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              credit ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 32,
              color: amountColor,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            '${credit ? '+' : ''}${_money.format(tx.amount)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: amountColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              tx.typeLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (tx.description.isNotEmpty) _row('Details', tx.description),
        if ((tx.reference ?? '').isNotEmpty) _row('Reference', tx.reference!),
        _row('Date', _when),
        if (tx.balanceBefore != null) _row('Before balance', _money.format(tx.balanceBefore)),
        if (tx.balanceAfter != null) _row('After balance', _money.format(tx.balanceAfter)),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
