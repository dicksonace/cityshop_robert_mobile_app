import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// Full-screen success after a wallet transfer or QR payment — matches the
/// familiar "Payment Successful" layout with a large amount and a single Done.
class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.amount,
    required this.recipientName,
    this.reference,
    this.note,
    this.onDone,
  });

  final double amount;
  final String recipientName;
  final String? reference;
  final String? note;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final ref = (reference ?? '').trim();
    final memo = (note ?? '').trim();

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1677FF),
              Color(0xFF4B9BFF),
              Color(0xFFE8F3FF),
              Colors.white,
            ],
            stops: [0.0, 0.22, 0.45, 0.72],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    const Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.white, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Payment Successful',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _finish(context),
                      child: const Text(
                        'Home',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _money.format(amount),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 40,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    _row('To', recipientName),
                    _row('Amount', _money.format(amount)),
                    _row('Payment method', 'Balance'),
                    if (memo.isNotEmpty) _row('Note', memo),
                    if (ref.isNotEmpty) _row('Reference', ref),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => _finish(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1677FF),
                      side: const BorderSide(color: Color(0xFF1677FF), width: 1.4),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _finish(BuildContext context) {
    if (onDone != null) {
      onDone!();
      return;
    }
    Navigator.of(context).pop();
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pushes [PaymentSuccessScreen] and waits until the user taps Done / Home.
Future<void> showPaymentSuccess(
  BuildContext context, {
  required double amount,
  required String recipientName,
  String? reference,
  String? note,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PaymentSuccessScreen(
        amount: amount,
        recipientName: recipientName,
        reference: reference,
        note: note,
      ),
    ),
  );
}
