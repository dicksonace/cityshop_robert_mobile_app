import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/reset_via_picker.dart';

/// Request a 6-digit email or SMS code, then set a new login password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialLogin = ''});

  final String initialLogin;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _login;
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _sending = false;
  bool _saving = false;
  bool _codeSent = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String _via = 'sms';
  String? _hint;

  @override
  void initState() {
    super.initState();
    _login = TextEditingController(text: widget.initialLogin);
    final initial = widget.initialLogin.trim();
    if (initial.contains('@')) {
      _via = 'email';
    }
  }

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _viaLabel => _via == 'sms' ? 'SMS' : 'email';

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  Future<void> _sendCode() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      _toast('Enter your mobile or email', error: true);
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await context.read<AppStore>().forgotPassword(
            login: login,
            via: _via,
          );
      if (!mounted) return;
      final hint = (result['hint'] as String?) ?? (result['email_hint'] as String?);
      setState(() {
        _codeSent = true;
        _hint = hint;
      });
      _toast(
        hint != null && hint.isNotEmpty
            ? 'Code sent to $hint via $_viaLabel'
            : (result['message'] as String? ?? 'If that account exists, a code was sent.'),
      );
    } on ApiException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reset() async {
    final login = _login.text.trim();
    if (_code.text.trim().length != 6) {
      _toast('Enter the 6-digit code from your $_viaLabel', error: true);
      return;
    }
    if (_password.text.length < 8) {
      _toast('Password must be at least 8 characters', error: true);
      return;
    }
    if (_password.text != _confirm.text) {
      _toast('Passwords do not match', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final message = await context.read<AppStore>().resetPassword(
            login: login,
            code: _code.text.trim(),
            password: _password.text,
            passwordConfirmation: _confirm.text,
          );
      if (!mounted) return;
      _toast(message);
      context.go('/login');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Forgot password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.ringOrange),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Reset password',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _codeSent
                      ? 'Enter the code we sent by $_viaLabel, then choose a new password.'
                      : 'Enter the mobile or email on your account, then choose Email or SMS.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                const Text('Mobile or Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _login,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: '0241234567 or email@example.com',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                if (!_codeSent) ...[
                  const SizedBox(height: 16),
                  ResetViaPicker(
                    value: _via,
                    onChanged: (via) => setState(() => _via = via),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _via == 'sms' ? 'Send SMS code' : 'Send email code',
                    loading: _sending,
                    onPressed: _sendCode,
                  ),
                ] else ...[
                  if (_hint != null && _hint!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Sent to $_hint via $_viaLabel',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Reset code', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '6-digit $_viaLabel code',
                      prefixIcon: const Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('New password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'At least 8 characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Confirm password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      hintText: 'Repeat new password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Update password',
                    loading: _saving,
                    onPressed: _reset,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _sending ? null : _sendCode,
                    child: Text(
                      _sending ? 'Sending…' : 'Resend $_viaLabel code',
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text(
                    'Back to login',
                    style: TextStyle(color: AppColors.textSecondary),
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
