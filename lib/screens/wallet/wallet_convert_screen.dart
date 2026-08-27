import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class WalletConvertScreen extends StatefulWidget {
  const WalletConvertScreen({super.key});

  @override
  State<WalletConvertScreen> createState() => _WalletConvertScreenState();
}

class _WalletConvertScreenState extends State<WalletConvertScreen> {
  String direction = 'ghs_to_rmb';
  final amountCtrl = TextEditingController();
  bool submitting = false;
  String? error;
  Map<String, dynamic>? quote;

  @override
  void dispose() {
    amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _quote() async {
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount < 1) {
      setState(() {
        quote = null;
        error = null;
      });
      return;
    }
    try {
      final q = await context.read<AppStore>().convertQuote(
            direction: direction,
            amount: amount,
          );
      if (!mounted) return;
      setState(() {
        quote = q;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        quote = null;
        error = e.toString();
      });
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount < 1) {
      setState(() => error = 'Enter at least 1.00');
      return;
    }

    final store = context.read<AppStore>();
    if (!(store.user?.canStoreWalletFunds ?? false)) {
      setState(() => error = 'Approve your Ghana Card (KYC) before converting.');
      return;
    }
    if (!(store.user?.hasPaymentPin ?? false)) {
      setState(() => error = 'Set a 4-digit payment PIN in Profile first.');
      return;
    }

    final receiveLabel = quote?['result_label']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm exchange'),
        content: Text(
          direction == 'ghs_to_rmb'
              ? 'Convert ${_ghs.format(amount)} → ${receiveLabel.isEmpty ? 'RMB' : receiveLabel}?'
              : 'Convert ¥${amount.toStringAsFixed(2)} → ${receiveLabel.isEmpty ? 'GHS' : receiveLabel}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final pin = await promptPaymentPin(
      context,
      title: 'Confirm conversion',
      subtitle: 'Enter your 4-digit payment PIN',
    );
    if (pin == null || !mounted) return;

    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final result = await store.convertWallet(
        direction: direction,
        amount: amount,
        paymentPin: pin,
      );
      if (!mounted) return;
      final message = result['message']?.toString() ?? 'Converted';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      context.go('/wallet/china-rmb');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final wallet = store.wallet;
    final kycOk = store.user?.canStoreWalletFunds ?? false;
    final hasPin = store.user?.hasPaymentPin ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Convert')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!kycOk)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'KYC required before convert.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/kyc'),
                    child: const Text('Verify'),
                  ),
                ],
              ),
            ),
          if (!hasPin)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Set a payment PIN in Profile first.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/profile/payment-pin'),
                    child: const Text('Set PIN'),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GHS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      Text(_ghs.format(wallet?.availableBalance ?? 0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('RMB', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      Text('¥${(wallet?.rmbBalance ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DirChip(
                  label: 'GHS → RMB',
                  selected: direction == 'ghs_to_rmb',
                  onTap: () {
                    setState(() => direction = 'ghs_to_rmb');
                    _quote();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DirChip(
                  label: 'RMB → GHS',
                  selected: direction == 'rmb_to_ghs',
                  onTap: () {
                    setState(() => direction = 'rmb_to_ghs');
                    _quote();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: direction == 'ghs_to_rmb' ? 'GHS amount' : 'RMB amount',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _quote(),
          ),
          if (quote != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quote!['rate_label']?.toString() ?? '', style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  Text(
                    'You receive: ${quote!['result_label'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: submitting ? 'Converting…' : 'Review & convert',
            onPressed: submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _DirChip extends StatelessWidget {
  const _DirChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 2),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? AppColors.primary : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
