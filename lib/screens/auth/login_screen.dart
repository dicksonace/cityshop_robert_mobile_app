import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../services/push_notifications.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/otp_code_boxes.dart';
import '../../widgets/auth_help_link.dart';
import '../../widgets/common_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;
  String _portal = 'buyer';
  PendingMfa? _pending;
  String _method = 'email';

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_login.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your mobile/email and password')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final store = context.read<AppStore>();
      final pending = await store.login(
        login: _login.text.trim(),
        password: _password.text,
        portal: _portal,
      );
      if (pending != null) {
        if (!mounted) return;
        setState(() {
          _pending = pending;
          _method = pending.methods.contains('email') ? 'email' : 'totp';
        });
        return;
      }
      await PushNotifications.instance.syncForLoggedInUser(requestIfNeeded: true);
      if (!mounted) return;
      context.go(store.homePath);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitCode() async {
    if (_loading) return;
    final pending = _pending;
    if (pending == null || _code.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the 6-digit code')));
      return;
    }
    setState(() => _loading = true);
    try {
      final store = context.read<AppStore>();
      await store.completeMfa(token: pending.token, method: _method, code: _code.text.trim());
      await PushNotifications.instance.syncForLoggedInUser(requestIfNeeded: true);
      if (!mounted) return;
      context.go(store.homePath);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pending != null) {
      return _codeStep();
    }
    final isSeller = _portal == 'seller';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/shop'),
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
                Text(
                  isSeller ? 'SELLER' : 'SHOPPER',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  isSeller
                      ? 'Login to your Seller Hub dashboard.'
                      : 'Login to shop, track orders, and save wishlists.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'buyer', label: Text('Shopper'), icon: Icon(Icons.shopping_bag_outlined, size: 18)),
                    ButtonSegment(value: 'seller', label: Text('Seller'), icon: Icon(Icons.storefront_outlined, size: 18)),
                  ],
                  selected: {_portal},
                  onSelectionChanged: (set) => setState(() => _portal = set.first),
                ),
                const SizedBox(height: 24),
                const Text('Mobile or Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _login,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: '0241234567 or Email@example.com',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      activeColor: AppColors.accent,
                      onChanged: (v) => setState(() => _remember = v ?? true),
                    ),
                    const Text('Remember me', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push(
                        '/forgot-password',
                        extra: _login.text.trim(),
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: isSeller ? 'Login as seller' : 'Login',
                  loading: _loading,
                  onPressed: _submit,
                ),
                if (!isSeller) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text.rich(
                      TextSpan(
                        text: 'New here? ',
                        style: TextStyle(color: AppColors.textSecondary),
                        children: [
                          TextSpan(
                            text: 'Create shopper account',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text(
                    'Seller registration stays on the website invite link.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 8),
                const AuthHelpLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeStep() {
    final pending = _pending!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _pending = null),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Enter your sign-in code', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Password accepted. Finish with the method you turned on.'),
          if (pending.methods.length > 1) ...[
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                if (pending.methods.contains('email'))
                  ButtonSegment(value: 'email', label: Text(pending.codeChannel == 'email' ? 'Email' : 'SMS')),
                if (pending.methods.contains('totp')) const ButtonSegment(value: 'totp', label: Text('Authenticator')),
              ],
              selected: {_method},
              onSelectionChanged: (value) {
                _code.clear();
                setState(() => _method = value.first);
              },
            ),
          ],
          const SizedBox(height: 16),
          Text(
            _method == 'email' ? (pending.codeChannel == 'email' ? 'Email code' : 'SMS code') : 'Authenticator code',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          OtpCodeBoxes(controller: _code, onCompleted: (_) => _submitCode()),
          const SizedBox(height: 8),
          Text(
            _method == 'email'
                ? 'Sent to ${pending.emailHint ?? (pending.codeChannel == 'email' ? 'your email' : 'your phone')}.'
                : 'Code from the app you scanned.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _submitCode,
            child: Text(_loading ? 'Checking…' : 'Continue'),
          ),
          if (_method == 'email')
            TextButton(
              onPressed: _loading
                  ? null
                  : () async {
                      try {
                        await context.read<AppStore>().resendMfaEmail(pending.token);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pending.codeChannel == 'email' ? 'A new code was emailed.' : 'A new code was sent by SMS.')));
                      } on ApiException catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
              child: Text(pending.codeChannel == 'email' ? 'Send a new email code' : 'Send a new SMS code'),
            ),
        ],
      ),
    );
  }
}
