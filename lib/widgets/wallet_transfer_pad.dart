import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../screens/cart/paystack_payment_screen.dart';
import '../store/app_store.dart';
import 'payment_success_screen.dart';

final _money = NumberFormat.currency(locale: 'en_GH', symbol: 'GH₵', decimalDigits: 2);

/// WeChat-style transfer pad used by chat transfer and QR scan-to-pay.
class WalletTransferPad extends StatefulWidget {
  const WalletTransferPad({
    super.key,
    required this.recipientName,
    required this.onSubmit,
    this.recipientMobile,
    this.recipientAvatar,
    this.lockedAmount,
    this.initialNote,
    this.actionLabel = 'Transfer',
    this.onBack,
    this.qrPayload,
  });

  final String recipientName;
  final String? recipientMobile;
  final String? recipientAvatar;
  /// When set (e.g. fixed-amount QR), keypad edits are disabled.
  final double? lockedAmount;
  /// Prefills the note (e.g. reason baked into a request QR).
  final String? initialNote;
  final String actionLabel;
  final VoidCallback? onBack;
  final Future<void> Function(double amount, String? note) onSubmit;

  /// When set, a short wallet balance opens Mobile Money / card and sends
  /// that payment to this QR instead of only topping up the payer.
  final String? qrPayload;

  @override
  State<WalletTransferPad> createState() => _WalletTransferPadState();
}

class _WalletTransferPadState extends State<WalletTransferPad> {
  late String _amount;
  final _note = TextEditingController();
  bool showNote = false;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    final locked = widget.lockedAmount;
    _amount = locked != null && locked > 0 ? locked.toStringAsFixed(2) : '';
    final seedNote = (widget.initialNote ?? '').trim();
    if (seedNote.isNotEmpty) {
      _note.text = seedNote;
      showNote = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadWallet();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _locked => widget.lockedAmount != null && widget.lockedAmount! > 0;

  double? get _parsedAmount {
    if (_amount.isEmpty) return null;
    return double.tryParse(_amount);
  }

  Future<void> _send() async {
    final parsed = _parsedAmount;
    if (parsed == null || parsed < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least GH₵1.00')),
      );
      return;
    }

    final available = context.read<AppStore>().wallet?.availableBalance ?? 0;
    if (parsed > available) {
      final payload = widget.qrPayload;
      if (payload != null && payload.isNotEmpty) {
        await _openDirectPay(parsed);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough balance (${_money.format(available)}). Add money via Mobile Money / Card first.',
          ),
        ),
      );
      return;
    }

    setState(() => sending = true);
    try {
      await widget.onSubmit(
        parsed,
        showNote && _note.text.trim().isNotEmpty ? _note.text.trim() : null,
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _openDirectPay(double amount) async {
    final payload = widget.qrPayload;
    if (payload == null || payload.isEmpty) return;
    if (amount < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile Money and card start at GH₵5.00')),
      );
      return;
    }

    final wallet = context.read<AppStore>().wallet;
    final paystack = wallet?.paystackConfigured == true;
    final flutterwave = wallet?.flutterwaveConfigured == true;
    if (!paystack && !flutterwave) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card and Mobile Money are not available right now')),
      );
      return;
    }

    final available = wallet?.availableBalance ?? 0;
    final choice = await showModalBottomSheet<_DirectPayChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => _DirectPaySheet(
        recipientName: widget.recipientName,
        amount: amount,
        available: available,
        paystack: paystack,
        flutterwave: flutterwave,
      ),
    );
    if (choice == null || !mounted) return;

    final note = showNote && _note.text.trim().isNotEmpty ? _note.text.trim() : null;
    final store = context.read<AppStore>();
    try {
      final started = await store.initializeQrGatewayPay(
        payload: payload,
        amount: amount,
        method: choice.method,
        gateway: choice.gateway,
        note: note,
      );
      if (!mounted) return;
      final url = started['authorization_url'] as String? ?? '';
      final reference = started['reference'] as String? ?? '';
      if (url.isEmpty || reference.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start payment')),
        );
        return;
      }

      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PaystackPaymentScreen(
            authorizationUrl: url,
            reference: reference,
            onVerify: (ref) => store.verifyQrGatewayPay(reference: ref, gateway: choice.gateway),
          ),
        ),
      );
      if (!mounted || paid != true) return;
      await showPaymentSuccess(
        context,
        amount: amount,
        recipientName: widget.recipientName,
        reference: reference,
        note: note,
      );
      if (!mounted) return;
      context.go('/shop?tab=wallet');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _appendDigit(String digit) {
    if (_locked) return;
    if (digit == '.' && _amount.contains('.')) return;
    if (_amount == '0' && digit != '.') {
      setState(() => _amount = digit);
      return;
    }
    final next = '$_amount$digit';
    final parts = next.split('.');
    if (parts[0].length > 8) return;
    if (parts.length > 1 && parts[1].length > 2) return;
    setState(() => _amount = next);
  }

  void _backspace() {
    if (_locked) return;
    if (_amount.isEmpty) return;
    setState(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  Widget _keyCell({
    required VoidCallback? onTap,
    Widget? child,
    String? label,
    Color? background,
  }) {
    return Material(
      color: background ?? Colors.white,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: Center(
          child: child ??
              Text(
                label ?? '',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111111),
                ),
              ),
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    final letter = widget.recipientName.trim().isNotEmpty
        ? widget.recipientName.trim()[0].toUpperCase()
        : '?';
    return ColoredBox(
      color: const Color(0xFF07C160),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<AppStore>().wallet;
    final available = wallet?.availableBalance ?? 0;
    final canSend = (_parsedAmount ?? 0) >= 1 && !sending;
    final canPayDirect = widget.qrPayload != null && widget.qrPayload!.isNotEmpty;
    final amount = _parsedAmount ?? 0;
    final balanceCovers = amount >= 1 && amount <= available;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final avatar = widget.recipientAvatar;
    final mobile = (widget.recipientMobile ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF111111)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Transfer to ${widget.recipientName}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111111),
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Balance: ${_money.format(available)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF888888),
                                  height: 1.2,
                                ),
                              ),
                              if (mobile.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  mobile,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFB2B2B2),
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: avatar != null && avatar.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: ApiConfig.resolveMediaUrl(avatar),
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => _avatarFallback(),
                                  )
                                : _avatarFallback(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    const Text(
                      'Transfer amount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF888888),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'GH₵',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111111),
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _amount,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111111),
                            height: 1,
                          ),
                        ),
                        if (!_locked)
                          Container(
                            width: 2,
                            height: 34,
                            margin: const EdgeInsets.only(left: 3),
                            color: const Color(0xFF07C160),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(height: 0.5, color: const Color(0xFFE5E5E5)),
                    const SizedBox(height: 10),
                    if (!showNote)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () => setState(() => showNote = true),
                          child: const Text(
                            'Add Note',
                            style: TextStyle(
                              color: Color(0xFF576B95),
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      )
                    else
                      TextField(
                        controller: _note,
                        autofocus: true,
                        maxLength: 120,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'Add a note',
                          hintStyle: TextStyle(color: Color(0xFFB2B2B2)),
                          border: InputBorder.none,
                          isDense: true,
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const Spacer(),
                    _PaymentMethodRow(
                      available: available,
                      amount: amount,
                      onTopUp: () {
                        if (canPayDirect && amount >= 1) {
                          _openDirectPay(amount);
                        } else {
                          context.go('/shop?tab=wallet');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: const Color(0xFFD2D3D8),
              padding: EdgeInsets.only(bottom: bottomPad),
              child: SizedBox(
                height: 256,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          for (final row in const [
                            ['1', '2', '3'],
                            ['4', '5', '6'],
                            ['7', '8', '9'],
                            ['', '0', '.'],
                          ])
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final key in row)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(0.4),
                                        child: key.isEmpty
                                            ? const ColoredBox(color: Color(0xFFD2D3D8))
                                            : _keyCell(
                                                label: key,
                                                onTap: _locked ? null : () => _appendDigit(key),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(0.4),
                              child: _keyCell(
                                onTap: _locked ? null : _backspace,
                                background: const Color(0xFFE8E9ED),
                                child: const Icon(Icons.backspace_outlined, size: 22, color: Color(0xFF111111)),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(0.4),
                              child: Material(
                                color: canSend && (balanceCovers || canPayDirect)
                                    ? const Color(0xFF07C160)
                                    : const Color(0xFF07C160).withValues(alpha: 0.35),
                                child: InkWell(
                                  onTap: canSend && (balanceCovers || canPayDirect) ? _send : null,
                                  child: Center(
                                    child: sending
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            widget.actionLabel,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodRow extends StatelessWidget {
  const _PaymentMethodRow({
    required this.available,
    required this.amount,
    required this.onTopUp,
  });

  final double available;
  final double amount;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final hasAmount = amount >= 1;
    final sufficient = hasAmount && amount <= available;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: sufficient ? const Color(0xFFF0FDF4) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sufficient ? const Color(0xFFBBF7D0) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: sufficient ? const Color(0xFF07C160) : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 20,
                  color: sufficient ? Colors.white : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Balance',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    Text(
                      sufficient
                          ? 'Pay from wallet · ${_money.format(available)} available'
                          : hasAmount
                              ? 'Insufficient · ${_money.format(available)} available'
                              : '${_money.format(available)} available',
                      style: TextStyle(
                        fontSize: 12,
                        color: sufficient
                            ? const Color(0xFF047857)
                            : (hasAmount ? const Color(0xFFDC2626) : const Color(0xFF888888)),
                      ),
                    ),
                  ],
                ),
              ),
              if (sufficient)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF07C160), size: 22),
            ],
          ),
        ),
        if (hasAmount && !sufficient) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onTopUp,
              child: const Text('Add money via Mobile Money / Card'),
            ),
          ),
        ],
      ],
    );
  }
}

class _DirectPayChoice {
  const _DirectPayChoice({required this.gateway, required this.method});

  final String gateway;
  final String method;
}

class _DirectPaySheet extends StatefulWidget {
  const _DirectPaySheet({
    required this.recipientName,
    required this.amount,
    required this.available,
    required this.paystack,
    required this.flutterwave,
  });

  final String recipientName;
  final double amount;
  final double available;
  final bool paystack;
  final bool flutterwave;

  @override
  State<_DirectPaySheet> createState() => _DirectPaySheetState();
}

class _DirectPaySheetState extends State<_DirectPaySheet> {
  late String _gateway = widget.flutterwave ? 'flutterwave' : 'paystack';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Text(
                    widget.recipientName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _money.format(widget.amount),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Goes to ${widget.recipientName}',
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                ],
              ),
            ),
            if (widget.paystack && widget.flutterwave)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'flutterwave', label: Text('Flutterwave')),
                    ButtonSegment(value: 'paystack', label: Text('Paystack')),
                  ],
                  selected: {_gateway},
                  onSelectionChanged: (value) => setState(() => _gateway = value.first),
                ),
              ),
            _option(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Balance',
              subtitle: 'Insufficient · ${_money.format(widget.available)} available',
              enabled: false,
              onTap: null,
            ),
            _option(
              icon: Icons.phone_android_rounded,
              title: 'Mobile Money',
              subtitle: 'Pay ${_money.format(widget.amount)} to ${widget.recipientName}',
              enabled: true,
              onTap: () => Navigator.pop(context, _DirectPayChoice(gateway: _gateway, method: 'momo')),
            ),
            _option(
              icon: Icons.credit_card_rounded,
              title: 'Card',
              subtitle: 'Pay ${_money.format(widget.amount)} to ${widget.recipientName}',
              enabled: true,
              onTap: () => Navigator.pop(context, _DirectPayChoice(gateway: _gateway, method: 'card')),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? const Color(0xFF111111) : const Color(0xFF9CA3AF)),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: enabled ? const Color(0xFF111111) : const Color(0xFF9CA3AF),
        ),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
