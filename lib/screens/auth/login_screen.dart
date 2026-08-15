import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../services/push_notifications.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;
  String _portal = 'buyer';

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
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
      await store.login(
        login: _login.text.trim(),
        password: _password.text,
        portal: _portal,
      );
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

  @override
  Widget build(BuildContext context) {
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
                    hintText: '0241234567 or email@example.com',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
