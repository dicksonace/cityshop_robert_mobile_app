import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Set, change, or reset the buyer's 4-digit payment PIN.
class PaymentPinScreen extends StatefulWidget {
  const PaymentPinScreen({super.key});

  @override
  State<PaymentPinScreen> createState() => _PaymentPinScreenState();
}

class _PaymentPinScreenState extends State<PaymentPinScreen> {
  bool saving = false;
  bool resetting = false;
  String mode = 'manage'; // manage | reset
  String? emailHint;

  final pin = TextEditingController();
  final pinConfirm = TextEditingController();
  final currentPin = TextEditingController();
  final code = TextEditingController();

  @override
  void dispose() {
    pin.dispose();
    pinConfirm.dispose();
    currentPin.dispose();
    code.dispose();
    super.dispose();
  }

  bool get hasPin => context.read<AppStore>().user?.hasPaymentPin ?? false;

  Future<void> _setOrChange() async {
    final updating = hasPin;
    if (pin.text.length != 4 || pinConfirm.text.length != 4) {
      _toast('Enter a 4-digit PIN twice');
      return;
    }
    if (pin.text != pinConfirm.text) {
      _toast('PINs do not match');
      return;
    }
    if (updating && currentPin.text.length != 4) {
      _toast('Enter your current PIN');
      return;
    }

    setState(() => saving = true);
    try {
      final store = context.read<AppStore>();
      if (updating) {
        await store.changePaymentPin(
          currentPin: currentPin.text,
          pin: pin.text,
          pinConfirmation: pinConfirm.text,
        );
      } else {
        await store.setPaymentPin(
          pin: pin.text,
          pinConfirmation: pinConfirm.text,
        );
      }
      if (!mounted) return;
      _toast(updating ? 'Payment PIN updated' : 'Payment PIN set');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _sendResetCode() async {
    setState(() => saving = true);
    try {
      final hint = await context.read<AppStore>().forgotPaymentPin();
      if (!mounted) return;
      setState(() {
        mode = 'reset';
        emailHint = hint;
        saving = false;
      });
      _toast('Reset code sent${hint != null ? ' to $hint' : ''}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => saving = false);
        _toast(e.message);
      }
    }
  }

  Future<void> _resetWithCode() async {
    if (code.text.trim().length != 6) {
      _toast('Enter the 6-digit email code');
      return;
    }
    if (pin.text.length != 4 || pinConfirm.text.length != 4) {
      _toast('Enter a new 4-digit PIN twice');
      return;
    }
    if (pin.text != pinConfirm.text) {
      _toast('PINs do not match');
      return;
    }

    setState(() => resetting = true);
    try {
      await context.read<AppStore>().resetPaymentPin(
            code: code.text.trim(),
            pin: pin.text,
            pinConfirmation: pinConfirm.text,
          );
      if (!mounted) return;
      _toast('Payment PIN reset');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _pinDecoration(String label) {
    return InputDecoration(
      labelText: label,
      counterText: '',
    );
  }

  Widget _pinField(TextEditingController ctrl, String label, {bool obscure = true}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _pinDecoration(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final has = context.watch<AppStore>().user?.hasPaymentPin ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(has ? 'Payment PIN' : 'Set payment PIN')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.ringOrange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              has
                  ? 'Your PIN protects wallet payments, MoMo withdrawals, and chat transfers.'
                  : 'Create a 4-digit PIN before paying with wallet, withdrawing, or sending money in chat.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
          const SizedBox(height: 20),
          if (mode == 'manage') ...[
            if (has) ...[
              _pinField(currentPin, 'Current PIN'),
              const SizedBox(height: 10),
            ],
            _pinField(pin, has ? 'New PIN' : 'PIN'),
            const SizedBox(height: 10),
            _pinField(pinConfirm, 'Confirm PIN'),
            const SizedBox(height: 20),
            PrimaryButton(
              label: has ? 'Update PIN' : 'Set PIN',
              loading: saving,
              onPressed: saving ? null : _setOrChange,
            ),
            if (has) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: saving ? null : _sendResetCode,
                child: const Text('Forgot PIN? Reset via email'),
              ),
            ],
          ] else ...[
            Text(
              emailHint == null
                  ? 'Enter the 6-digit code we sent to your email, then choose a new PIN.'
                  : 'Enter the 6-digit code sent to $emailHint, then choose a new PIN.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Email code', counterText: ''),
            ),
            const SizedBox(height: 10),
            _pinField(pin, 'New PIN'),
            const SizedBox(height: 10),
            _pinField(pinConfirm, 'Confirm new PIN'),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Reset PIN',
              loading: resetting,
              onPressed: resetting ? null : _resetWithCode,
            ),
            TextButton(
              onPressed: () => setState(() => mode = 'manage'),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: saving ? null : _sendResetCode,
              child: const Text('Resend code'),
            ),
          ],
        ],
      ),
    );
  }
}
