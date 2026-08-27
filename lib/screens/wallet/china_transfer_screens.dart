import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

String _formatBuyRate(double n) {
  if (n <= 0) return '—';
  final s = n.toStringAsFixed(4);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _optionalRecipientLabel(Map<String, dynamic> field) {
  final name = (field['name'] as String? ?? '').toLowerCase();
  if (name.contains('alipay') || name.contains('account')) return 'Alipay Account';
  if (name.contains('name')) return 'Recipient Name';
  if (name.contains('note')) return 'Notes';
  final label = (field['label'] as String? ?? 'Field').trim();
  return label.replaceAll(RegExp(r'\s*\*$'), '');
}

String _optionalRecipientHint(Map<String, dynamic> field) {
  final name = (field['name'] as String? ?? '').toLowerCase();
  if (name.contains('alipay') || name.contains('account')) return "Recipient's Alipay ID";
  if (name.contains('name')) return 'Name of recipient';
  if (name.contains('note')) return 'Any additional information';
  return (field['placeholder'] as String?) ?? '';
}

/// Buy RMB calculator: Today's Rate, You send / They receive, arrival, Continue.
class BuyRmbCalculatorCard extends StatefulWidget {
  const BuyRmbCalculatorCard({
    super.key,
    required this.ghsPerRmb,
    required this.rmbPerGhs,
    required this.feeMode,
    required this.feeValue,
    required this.enabled,
    this.initialGhs,
    required this.onContinue,
  });

  final double ghsPerRmb;
  final double rmbPerGhs;
  final String feeMode;
  final double feeValue;
  final bool enabled;
  final String? initialGhs;
  final void Function(String ghsAmount) onContinue;

  @override
  State<BuyRmbCalculatorCard> createState() => _BuyRmbCalculatorCardState();
}

class _BuyRmbCalculatorCardState extends State<BuyRmbCalculatorCard> {
  late final TextEditingController ghs;
  late final TextEditingController cny;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    final start = widget.initialGhs?.trim() ?? '';
    ghs = TextEditingController(text: start);
    final send = double.tryParse(start) ?? 0;
    cny = TextEditingController(
      text: send > 0 && widget.ghsPerRmb > 0
          ? (send / widget.ghsPerRmb).toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    ghs.dispose();
    cny.dispose();
    super.dispose();
  }

  void _fromGhs(String raw) {
    if (syncing) return;
    syncing = true;
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned != raw) {
      ghs.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    final send = double.tryParse(cleaned) ?? 0;
    if (send > 0 && widget.ghsPerRmb > 0) {
      cny.text = (send / widget.ghsPerRmb).toStringAsFixed(2);
    } else {
      cny.text = '';
    }
    syncing = false;
    setState(() {});
  }

  void _fromCny(String raw) {
    if (syncing) return;
    syncing = true;
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned != raw) {
      cny.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    final receive = double.tryParse(cleaned) ?? 0;
    if (receive > 0 && widget.ghsPerRmb > 0) {
      ghs.text = (receive * widget.ghsPerRmb).toStringAsFixed(2);
    } else {
      ghs.text = '';
    }
    syncing = false;
    setState(() {});
  }

  double get send => double.tryParse(ghs.text) ?? 0;
  double get receive =>
      widget.ghsPerRmb > 0 && send > 0 ? send / widget.ghsPerRmb : 0;
  double get fee =>
      widget.feeMode == 'percent' ? send * widget.feeValue / 100 : widget.feeValue;
  bool get canContinue => widget.enabled && send > 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF5B21B6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF7C3AED), width: 1.5),
            ),
            child: Column(
              children: [
                const Text(
                  'GHS to RMB',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1 GHS → ${_formatBuyRate(widget.rmbPerGhs)} RMB',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('You send', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563))),
          const SizedBox(height: 8),
          _AmountField(
            symbol: '₵',
            code: 'GHS',
            controller: ghs,
            onChanged: _fromGhs,
          ),
          const SizedBox(height: 14),
          const Text('They receive', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563))),
          const SizedBox(height: 8),
          _AmountField(
            symbol: '¥',
            code: 'CNY',
            controller: cny,
            onChanged: _fromCny,
          ),
          if (fee > 0 && send > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Fee ${_ghs.format(fee)} · Total ${_ghs.format(send + fee)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Arrives in 5–30 minutes',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF059669),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: canContinue ? () => widget.onContinue(send.toStringAsFixed(2)) : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(
                widget.enabled ? 'Continue' : 'Transfers paused',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountField extends StatefulWidget {
  const _AmountField({
    required this.symbol,
    required this.code,
    required this.controller,
    required this.onChanged,
  });

  final String symbol;
  final String code;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: focused ? Colors.white : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: focused ? const Color(0xFF6366F1) : const Color(0xFFE5E7EB),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(
              widget.symbol,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: widget.onChanged,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                // Avoid ListView centering the focused field (looks like the page is
                // split in half with a blank region under Continue).
                scrollPadding: const EdgeInsets.only(bottom: 24),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '0.00',
                  hintStyle: TextStyle(color: Color(0xFFD1D5DB), fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.code,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF4B5563)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChinaTransferHubScreen extends StatefulWidget {
  const ChinaTransferHubScreen({super.key});

  @override
  State<ChinaTransferHubScreen> createState() => _ChinaTransferHubScreenState();
}

class _ChinaTransferHubScreenState extends State<ChinaTransferHubScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> config = {};
  List<Map<String, dynamic>> transfers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadChinaTransfers();
      if (!mounted) return;
      setState(() {
        config = Map<String, dynamic>.from(data['config'] as Map? ?? {});
        transfers = (data['transfers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Map<String, dynamic>? get rate =>
      config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;

  @override
  Widget build(BuildContext context) {
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? 0;
    final rmbPerGhs = (rate?['rmb_per_ghs'] as num?)?.toDouble() ??
        (ghsPerRmb > 0 ? 1 / ghsPerRmb : 0);
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    final enabled = config['enabled'] == true;
    final minGhs = (rate?['min_ghs'] as num?)?.toDouble();

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Buy RMB')),
      body: loading
          ? const FullPageLoader(label: 'Loading rates…')
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                  children: [
                    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                    Text(
                      'Send GHS, receive CNY in China via Alipay.',
                      style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    if (rate != null)
                      BuyRmbCalculatorCard(
                        ghsPerRmb: ghsPerRmb,
                        rmbPerGhs: rmbPerGhs,
                        feeMode: feeMode,
                        feeValue: feeValue,
                        enabled: enabled,
                        initialGhs: minGhs != null && minGhs > 0 ? minGhs.toStringAsFixed(0) : null,
                        onContinue: (amount) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          context.push('/wallet/china-transfer/create', extra: amount);
                        },
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFD1D5DB), style: BorderStyle.solid),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'Rate not published yet',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'China transfers will open here once admin publishes a rate.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text('Your transfers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (transfers.isEmpty)
                      const Text('No China transfers yet.', style: TextStyle(color: Colors.black54)),
                    ...transfers.map((item) {
                      final quote =
                          item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          '${_ghs.format((quote['total_payable_ghs'] as num?)?.toDouble() ?? 0)} → ¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                        ),
                        trailing: Text(
                          '${item['status_label']}',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                        ),
                        onTap: () => context.push('/wallet/china-transfer/${item['id']}'),
                      );
                    }),
                  ],
                ),
              ),
            ),
    );
  }
}

class ChinaTransferCreateScreen extends StatefulWidget {
  const ChinaTransferCreateScreen({super.key, this.initialGhs});

  final String? initialGhs;

  @override
  State<ChinaTransferCreateScreen> createState() => _ChinaTransferCreateScreenState();
}

class _ChinaTransferCreateScreenState extends State<ChinaTransferCreateScreen> {
  Map<String, dynamic> config = {};
  bool loading = true;
  bool submitting = false;
  String? error;
  final amount = TextEditingController();
  final values = <int, String>{};
  final files = <int, XFile>{};

  @override
  void initState() {
    super.initState();
    amount.text = widget.initialGhs ?? '1000';
    _load();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final store = context.read<AppStore>();
      await store.loadWallet();
      final data = await store.loadChinaTransfers();
      if (!mounted) return;
      final cfg = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      setState(() {
        config = cfg;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get fields => (config['fields'] as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  List<Map<String, dynamic>> get recipientFields => fields.where((f) {
        final g = (f['group'] as String? ?? '').toLowerCase();
        return !['payment', 'payment_proof', 'proof'].contains(g);
      }).toList();

  bool _isQrField(Map<String, dynamic> field) {
    final type = field['type'] as String? ?? 'text';
    final blob = '${field['name'] ?? ''} ${field['label'] ?? ''}'.toLowerCase();
    return ['image', 'document', 'files'].contains(type) || blob.contains('qr');
  }

  List<Map<String, dynamic>> get qrFields => recipientFields.where(_isQrField).toList();
  List<Map<String, dynamic>> get textRecipientFields => recipientFields
      .where((f) => !_isQrField(f))
      .where((f) {
        final name = (f['name'] as String? ?? '').toLowerCase();
        // Hide phone / address — rmb-wallet only shows account, name, notes.
        return !name.contains('phone') && name != 'recipient_address';
      })
      .toList();

  Future<void> _submit() async {
    final store = context.read<AppStore>();
    if (!(store.user?.canStoreWalletFunds ?? false)) {
      setState(() => error = 'Approve your Ghana Card (KYC) before transferring.');
      return;
    }
    if (!(store.user?.hasPaymentPin ?? false)) {
      setState(() => error = 'Set a 4-digit payment PIN in Profile first.');
      return;
    }

    final pin = await promptPaymentPin(
      context,
      title: 'Confirm Alipay transfer',
      subtitle: 'Authorize this transfer with your payment PIN',
    );
    if (pin == null || !mounted) return;

    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final created = await store.submitChinaTransfer(
            fundingSource: 'ghs_wallet',
            ghsAmount: amount.text,
            paymentMethodId: null,
            paymentPin: pin,
            fields: values,
            files: files,
          );
      if (!mounted) return;
      context.go('/wallet/china-transfer/${created['id']}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final kycOk = store.user?.canStoreWalletFunds ?? false;
    final hasPin = store.user?.hasPaymentPin ?? false;
    final rate = config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? 0;
    final rmbPerGhs = (rate?['rmb_per_ghs'] as num?)?.toDouble() ??
        (ghsPerRmb > 0 ? 1 / ghsPerRmb : 0);
    final send = double.tryParse(amount.text) ?? 0;
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    // Same as rmb-wallet: They receive = You send × (1 GHS → RMB).
    final rmb = ghsPerRmb > 0 ? send / ghsPerRmb : 0.0;
    final fee = feeMode == 'percent' ? send * feeValue / 100 : feeValue;

    return Scaffold(
      appBar: AppBar(title: const Text('Submit Transfer Request')),
      resizeToAvoidBottomInset: true,
      body: loading
          ? const FullPageLoader(label: 'Loading form…')
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                if (!kycOk) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: Text('KYC required before transfer.', style: TextStyle(fontWeight: FontWeight.w600))),
                        TextButton(onPressed: () => context.push('/kyc'), child: const Text('Verify')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!hasPin) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Set a payment PIN in Profile first.', style: TextStyle(fontWeight: FontWeight.w600))),
                        TextButton(onPressed: () => context.push('/profile/payment-pin'), child: const Text('Set PIN')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('You send', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text(_ghs.format(send), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('They receive', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text('¥${rmb.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (rmbPerGhs > 0)
                        Text(
                          'Rate 1 GHS → ${_formatBuyRate(rmbPerGhs)} RMB',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4338CA)),
                        ),
                      if (rmbPerGhs > 0) const SizedBox(height: 4),
                      Text(
                        'Fee ${_ghs.format(fee)} · Total ${_ghs.format(send + fee)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF4338CA)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...qrFields.map((field) {
                  final id = (field['id'] as num).toInt();
                  final picked = files[id];
                  final required = field['required'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _AlipayQrUploadCard(
                      required: required,
                      helpText: (field['help_text'] as String?)?.isNotEmpty == true
                          ? '${field['help_text']}'
                          : 'Upload a clear Alipay receive QR',
                      file: picked,
                      onPick: () async {
                        final file = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (file != null) setState(() => files[id] = file);
                      },
                      onClear: picked == null
                          ? null
                          : () => setState(() => files.remove(id)),
                    ),
                  );
                }),
                ...textRecipientFields.map((field) {
                  final id = (field['id'] as num).toInt();
                  final type = field['type'] as String? ?? 'text';
                  // rmb-wallet: only QR is required — account / name / notes are optional.
                  final label = '${_optionalRecipientLabel(field)} (Optional)';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      onChanged: (v) => values[id] = v,
                      decoration: InputDecoration(
                        labelText: label,
                        hintText: _optionalRecipientHint(field),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: type == 'textarea' ? 3 : 1,
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pay from wallet balance',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Available: ${_ghs.format(store.wallet?.availableBalance ?? 0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total debit: ${_ghs.format(send + fee)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF047857)),
                      ),
                      if ((store.wallet?.availableBalance ?? 0) + 0.0001 < send + fee) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.push('/wallet/manual-deposit'),
                          child: const Text('Top up wallet'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    submitting ? 'Submitting…' : 'Submit Transfer Request',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

class ChinaTransferShowScreen extends StatefulWidget {
  const ChinaTransferShowScreen({super.key, required this.id});

  final int id;

  @override
  State<ChinaTransferShowScreen> createState() => _ChinaTransferShowScreenState();
}

class _ChinaTransferShowScreenState extends State<ChinaTransferShowScreen> {
  Map<String, dynamic>? transfer;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppStore>().fetchChinaTransfer(widget.id);
      if (!mounted) return;
      setState(() => transfer = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = transfer;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('China Transfer')),
        body: error != null ? Center(child: Text(error!)) : const FullPageLoader(label: 'Loading transfer…'),
      );
    }
    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : <String, dynamic>{};
    final timeline = (item['timeline'] as List? ?? []).whereType<Map>().toList();
    final fields = (item['fields'] as List? ?? []).whereType<Map>().toList();
    final proofs = (item['proofs'] as List? ?? []).whereType<Map>().where((p) => p['type'] == 'rmb_sent').toList();

    return Scaffold(
      appBar: AppBar(title: Text('${item['reference']}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('${item['status_label']}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            if ((item['funding_source_label'] as String?)?.isNotEmpty == true)
              Text('${item['funding_source_label']}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (item['funding_source'] == 'rmb_wallet')
              Text('RMB held: ¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}')
            else ...[
              Text('GHS paid: ${_ghs.format((quote['total_payable_ghs'] as num?)?.toDouble() ?? 0)}'),
              Text('Fee: ${_ghs.format((quote['fee_ghs'] as num?)?.toDouble() ?? 0)}'),
            ],
            Text('Exchange rate: 1 RMB = GH₵${((quote['ghs_per_rmb'] as num?)?.toDouble() ?? 0).toStringAsFixed(4)}'),
            Text('RMB amount: ¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
            const SizedBox(height: 20),
            ...timeline.map((step) {
              final current = step['current'] == true;
              final done = step['done'] == true;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  current ? Icons.radio_button_checked : done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: current ? AppColors.primary : done ? Colors.green : Colors.grey,
                ),
                title: Text('${step['label']}', style: TextStyle(fontWeight: current ? FontWeight.w800 : FontWeight.w500)),
              );
            }),
            if ((item['rejection_reason'] as String?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('${item['rejection_reason']}', style: const TextStyle(color: Colors.red)),
              ),
            if (proofs.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('RMB sent — proof', style: TextStyle(fontWeight: FontWeight.w800)),
              ...proofs.map((proof) {
                final url = proof['url'] as String?;
                return TextButton(
                  onPressed: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  child: Text('${proof['original_name'] ?? 'View proof'}'),
                );
              }),
            ],
            const SizedBox(height: 16),
            const Text('Submitted details', style: TextStyle(fontWeight: FontWeight.w800)),
            ...fields.map((field) {
              final url = field['file_url'] as String?;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${field['label']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                subtitle: url != null
                    ? GestureDetector(
                        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                        child: const Text('View file', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                      )
                    : Text('${field['value'] ?? '—'}'),
              );
            }),
            if (item['can_cancel'] == true)
              TextButton(
                onPressed: () async {
                  await context.read<AppStore>().cancelChinaTransfer(widget.id);
                  await _load();
                },
                child: const Text('Cancel transfer'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Payment-proof style upload: green check + size + Change / X + preview.
class _AlipayQrUploadCard extends StatelessWidget {
  const _AlipayQrUploadCard({
    required this.required,
    required this.helpText,
    required this.file,
    required this.onPick,
    this.onClear,
  });

  final bool required;
  final String helpText;
  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  Future<void> _openPreview(BuildContext context) async {
    if (file == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.file(File(file!.path), fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = file != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Upload Alipay QR Code',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black),
              ),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFDC2626)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(helpText, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: picked ? const Color(0xFFECFDF5) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked ? const Color(0xFF6EE7B7) : const Color(0xFFD1D5DB),
              width: picked ? 1.6 : 1.2,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: picked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              FutureBuilder<int>(
                                future: file!.length(),
                                builder: (context, snap) {
                                  final size = snap.data;
                                  return Text(
                                    size == null ? '…' : _formatFileSize(size),
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: onPick,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Change', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        if (onClear != null) ...[
                          const SizedBox(width: 6),
                          Material(
                            color: const Color(0xFFDC2626),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onClear,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _openPreview(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(file!.path),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Click image to view full size',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                    ),
                  ],
                )
              : InkWell(
                  onTap: onPick,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Column(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 40, color: Colors.grey.shade500),
                        const SizedBox(height: 10),
                        const Text(
                          "Upload recipient's Alipay QR code",
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563)),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: onPick,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          ),
                          child: const Text('Choose Image', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
