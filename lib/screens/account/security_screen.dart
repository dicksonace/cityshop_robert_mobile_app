import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/otp_code_boxes.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  Map<String, dynamic> _mfa = {};
  Map<String, dynamic>? _setup;
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mfa = await context.read<AppStore>().loadMfa();
      if (!mounted) return;
      setState(() {
        _mfa = mfa;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
      _password.clear();
      _code.clear();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security', style: TextStyle(fontWeight: FontWeight.w900)),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Email / Gmail'), Tab(text: 'Authenticator')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _tabs,
              builder: (context, _) => _tabs.index == 0 ? _emailTab() : _totpTab(),
            ),
    );
  }

  Widget _emailTab() {
    final enabled = _mfa['email_enabled'] == true;
    final hasEmail = _mfa['has_email'] == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        Text(
          hasEmail
              ? 'Codes are emailed to ${_mfa['email']}. Gmail and other inboxes both work.'
              : 'Add an email on your profile first.',
        ),
        if (enabled) ...[
          const SizedBox(height: 8),
          const Text('Email codes are on.', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF047857))),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        if (!enabled && hasEmail) ...[
          FilledButton(
            onPressed: () => _run(() => context.read<AppStore>().sendMfaEmail(_password.text)),
            child: const Text('Email me a code'),
          ),
          const SizedBox(height: 12),
          const Text('Code from the email', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          OtpCodeBoxes(controller: _code),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _run(() => context.read<AppStore>().confirmMfaEmail(_code.text.trim())),
            child: const Text('Turn on email codes'),
          ),
        ],
        if (enabled)
          OutlinedButton(
            onPressed: () => _run(() => context.read<AppStore>().disableMfaEmail(_password.text)),
            child: const Text('Turn off email codes'),
          ),
      ],
    );
  }

  Widget _totpTab() {
    final enabled = _mfa['totp_enabled'] == true;
    final url = '${_setup?['otpauth_url'] ?? ''}';
    final secret = '${_setup?['secret'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Scan the QR code with Google Authenticator, Authy, or a similar app. You can also type the setup code.'),
        if (enabled) ...[
          const SizedBox(height: 8),
          const Text('Authenticator is on.', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF047857))),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        if (!enabled)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              setState(() => _error = null);
              try {
                final setup = await context.read<AppStore>().startMfaTotp(_password.text);
                if (!mounted) return;
                setState(() => _setup = setup);
              } on ApiException catch (e) {
                setState(() => _error = e.message);
              }
            },
            child: const Text('Show QR code'),
          ),
        if (!enabled && url.isNotEmpty) ...[
          const SizedBox(height: 16),
          Center(child: QrImageView(data: url, size: 180, backgroundColor: Colors.white)),
          const SizedBox(height: 8),
          SelectableText('Setup code: $secret', textAlign: TextAlign.center),
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: secret)),
            child: const Text('Copy setup code'),
          ),
          const Text('Code from the authenticator app', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          OtpCodeBoxes(controller: _code),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _run(() async {
              await context.read<AppStore>().confirmMfaTotp(_code.text.trim());
              _setup = null;
            }),
            child: const Text('Turn on authenticator'),
          ),
        ],
        if (enabled)
          OutlinedButton(
            onPressed: () => _run(() => context.read<AppStore>().disableMfaTotp(_password.text)),
            child: const Text('Turn off authenticator'),
          ),
      ],
    );
  }
}
