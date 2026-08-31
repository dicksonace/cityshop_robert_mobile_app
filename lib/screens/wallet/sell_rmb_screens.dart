import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/momo_widgets.dart';
import 'china_transfer_screens.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _usd = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
final _transferStamp = DateFormat('d MMM yyyy, h:mm a');

void _popToChinaRmbHub(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/wallet/china-rmb');
  }
}

bool _sellTransferIsTerminal(String? status) {
  return [
    'completed',
    'cancelled',
    'rejected',
    'failed',
  ].contains(status);
}

String _formatSellWhen(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  try {
    return _transferStamp.format(DateTime.parse(raw).toLocal());
  } catch (_) {
    return raw;
  }
}

class SellRmbHubScreen extends StatefulWidget {
  const SellRmbHubScreen({super.key});

  @override
  State<SellRmbHubScreen> createState() => _SellRmbHubScreenState();
}

class _SellRmbHubScreenState extends State<SellRmbHubScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> config = {};
  List<Map<String, dynamic>> transfers = [];
  final amount = TextEditingController(text: '10000');
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    amount.dispose();
    super.dispose();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await context.read<AppStore>().loadSellRmb();
      if (!mounted) return;
      setState(() {
        config = Map<String, dynamic>.from(data['config'] as Map? ?? {});
        transfers = (data['transfers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        loading = false;
        error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) error = e.toString();
        loading = false;
      });
    }
  }

  Map<String, dynamic>? get rate =>
      config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;

  @override
  Widget build(BuildContext context) {
    final usdPerRmb = (rate?['usd_per_rmb'] as num?)?.toDouble() ?? 0;
    final ghsPerUsd = (rate?['ghs_per_usd'] as num?)?.toDouble() ?? 0;
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? (usdPerRmb * ghsPerUsd);
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    final rmb = double.tryParse(amount.text) ?? 0;
    final usdGross = usdPerRmb > 0 ? rmb * usdPerRmb : 0.0;
    final fee = feeMode == 'percent' ? usdGross * feeValue / 100 : feeValue;
    final ghsGross = rmb * ghsPerRmb;
    final feeGhs = usdGross > 0 ? ghsGross * (fee / usdGross) : 0.0;
    final ghsPayout = ghsGross - feeGhs;
    final live = config['live'] == true || (config['live'] == null && config['enabled'] == true);
    final open = config['open'] == true || (config['open'] == null && config['enabled'] == true);
    final statusMessage = () {
      final msg = config['status_message'] as String?;
      if (msg != null && msg.trim().isNotEmpty) return msg.trim();
      if (!live) return 'Sell RMB is paused by admin.';
      if (rate == null) return 'Buying rate not published yet.';
      if (!open) return 'Alipay QR not ready yet.';
      return null;
    }();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popToChinaRmbHub(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => _popToChinaRmbHub(context),
          ),
          automaticallyImplyLeading: false,
          title: const Text('Sell RMB'),
          actions: [
            if (!loading)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 6),
                        Text('Auto refresh', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => _load(),
            ),
          ],
        ),
        body: loading
            ? const FullPageLoader(label: 'Loading buying rate…')
            : RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF047857), Color(0xFF065F46)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'We buy your RMB',
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Send RMB · receive GHS · admin processes payout',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            rate == null
                                ? 'Buying rate not published yet'
                                : '1 RMB = GH₵${ghsPerRmb.toStringAsFixed(4)}',
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !live ? const Color(0xFFFFF7ED) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: !live ? const Color(0xFFFDBA74) : const Color(0xFFE5E7EB)),
                        ),
                        child: Text(
                          statusMessage,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: !live ? const Color(0xFF9A3412) : const Color(0xFF4B5563),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    if ((config['instructions'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Text('${config['instructions']}', style: const TextStyle(color: Color(0xFF065F46))),
                    ],
                    if (rate != null) ...[
                      const SizedBox(height: 18),
                      const Text('RMB amount to sell', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixText: '¥ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _row('You receive (GHS)', _ghs.format(ghsPayout), bold: true),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: open
                            ? () async {
                                await context.push(
                                  '/wallet/sell-rmb/create',
                                  extra: {
                                    'rmb': amount.text,
                                    'payout_currency': 'ghs',
                                  },
                                );
                                if (mounted) _load(silent: true);
                              }
                            : null,
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                        child: Text(
                          open
                              ? 'Continue'
                              : (statusMessage ?? 'Not available yet'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    BuyRmbRecentTransfersSection(
                      title: 'Your Sell RMB requests',
                      showAutoRefresh: true,
                      transfers: transfers,
                      sellFlowFor: (_) => true,
                      onTransferTap: (item) async {
                        await context.push('/wallet/sell-rmb/${item['id']}');
                        if (mounted) _load(silent: true);
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.black54, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}

class SellRmbCreateScreen extends StatefulWidget {
  const SellRmbCreateScreen({super.key, this.initialRmb, this.initialPayoutCurrency});

  final String? initialRmb;
  final String? initialPayoutCurrency;

  @override
  State<SellRmbCreateScreen> createState() => _SellRmbCreateScreenState();
}

class _SellRmbCreateScreenState extends State<SellRmbCreateScreen> {
  Map<String, dynamic> config = {};
  bool loading = true;
  bool submitting = false;
  String? error;
  int step = 0;
  final amount = TextEditingController();
  final alipayName = TextEditingController();
  final payoutName = TextEditingController();
  final payoutMobile = TextEditingController();
  String? momoNetwork;
  int? methodId;
  final values = <int, String>{};
  final files = <int, XFile>{};

  @override
  void initState() {
    super.initState();
    amount.text = widget.initialRmb ?? '100';
    _load();
  }

  @override
  void dispose() {
    amount.dispose();
    alipayName.dispose();
    payoutName.dispose();
    payoutMobile.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppStore>().loadSellRmb();
      if (!mounted) return;
      final cfg = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      final methods = (cfg['receive_methods'] as List? ?? []).whereType<Map>().toList();
      final open = cfg['open'] == true || (cfg['open'] == null && cfg['enabled'] == true);
      final userName = context.read<AppStore>().user?.name ?? '';
      final userMobile = context.read<AppStore>().user?.mobile ?? '';
      int? pickedMethodId;
      for (final raw in methods) {
        final method = Map<String, dynamic>.from(raw);
        final qr = ApiConfig.resolveMediaUrl(method['qr_url'] as String?);
        if (qr.isNotEmpty || method['type'] == 'bank' || method['type'] == 'other') {
          pickedMethodId = (method['id'] as num?)?.toInt();
          break;
        }
      }
      setState(() {
        config = cfg;
        methodId = pickedMethodId ?? (methods.isEmpty ? null : (methods.first['id'] as num?)?.toInt());
        if (!open) {
          error = (cfg['status_message'] as String?)?.trim().isNotEmpty == true
              ? cfg['status_message'] as String
              : 'Sell RMB is not available right now.';
        }
        if (payoutName.text.trim().isEmpty && userName.isNotEmpty) {
          payoutName.text = userName;
        }
        if (payoutMobile.text.trim().isEmpty && userMobile.isNotEmpty) {
          payoutMobile.text = userMobile;
        }
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

  List<Map<String, dynamic>> get methods => (config['receive_methods'] as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  int? _fieldId(String name) {
    for (final field in fields) {
      if (field['name'] == name) return (field['id'] as num?)?.toInt();
    }
    return null;
  }

  Map<String, dynamic>? get selectedMethod {
    for (final m in methods) {
      if ((m['id'] as num?)?.toInt() == methodId) return m;
    }
    return methods.isEmpty ? null : methods.first;
  }

  Map<String, dynamic>? get rate =>
      config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;

  double get ghsPerRmb {
    final usdPerRmb = (rate?['usd_per_rmb'] as num?)?.toDouble() ?? 0;
    final ghsPerUsd = (rate?['ghs_per_usd'] as num?)?.toDouble() ?? 0;
    return (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? (usdPerRmb * ghsPerUsd);
  }

  double get minRmb => (rate?['min_rmb'] as num?)?.toDouble() ?? 20;

  double get ghsPayout {
    final rmb = double.tryParse(amount.text) ?? 0;
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    final usdPerRmb = (rate?['usd_per_rmb'] as num?)?.toDouble() ?? 0;
    final usdGross = usdPerRmb > 0 ? rmb * usdPerRmb : 0.0;
    final fee = feeMode == 'percent' ? usdGross * feeValue / 100 : feeValue;
    final ghsGross = rmb * ghsPerRmb;
    final feeGhs = usdGross > 0 ? ghsGross * (fee / usdGross) : 0.0;
    return ghsGross - feeGhs;
  }

  void _prepareFieldValues() {
    values.clear();
    void setField(String name, String value) {
      final id = _fieldId(name);
      if (id != null && value.trim().isNotEmpty) values[id] = value.trim();
    }

    final sender = alipayName.text.trim();
    setField('rmb_sender_name', sender.isNotEmpty ? sender : (payoutName.text.trim().isNotEmpty ? payoutName.text.trim() : '—'));
    setField('alipay_or_wechat_account', '—');
    setField('payment_reference', '—');
    setField('payout_name', payoutName.text.trim());
    setField('payout_mobile', payoutMobile.text.trim());
    setField('payout_account_number', payoutMobile.text.trim());
    setField('payout_bank_name', momoNetworkLabel(momoNetwork));
  }

  String? _validateStep(int targetStep) {
    if (targetStep >= 1 && (methodId == null || selectedMethod == null)) {
      return 'Alipay receive method is not configured yet.';
    }
    if (targetStep >= 2) {
      final rmb = double.tryParse(amount.text);
      if (rmb == null || rmb < minRmb) {
        return 'Enter at least ¥${minRmb.toStringAsFixed(0)} RMB.';
      }
      final screenshotId = _fieldId('payment_screenshot');
      if (screenshotId == null || files[screenshotId] == null) {
        return 'Upload your Alipay payment screenshot.';
      }
    }
    if (targetStep >= 3) {
      if (momoNetwork == null || momoNetwork!.isEmpty) return 'Select your Mobile Money network.';
      if (payoutMobile.text.trim().length < 9) return 'Enter your MoMo number.';
      if (payoutName.text.trim().length < 2) return 'Enter the name on your MoMo account.';
    }
    return null;
  }

  Future<void> _submit() async {
    final validation = _validateStep(3);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    _prepareFieldValues();
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final created = await context.read<AppStore>().submitSellRmb(
            rmbAmount: amount.text,
            payoutCurrency: 'ghs',
            receiveMethodId: methodId ?? 0,
            fields: values,
            files: files,
          );
      if (!mounted) return;
      final transferId = switch (created['id']) {
        final num n => n.toInt(),
        final String s => int.tryParse(s),
        _ => null,
      };
      if (transferId == null || transferId <= 0) {
        setState(() {
          error = 'Sell RMB submitted, but we could not open the receipt. Check Recent activity.';
          submitting = false;
        });
        return;
      }
      context.go('/wallet/sell-rmb/$transferId', extra: created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        submitting = false;
      });
    }
  }

  Widget _stepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i <= step;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${i + 1}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : const Color(0xFF9CA3AF),
            ),
          ),
        );
      }),
    );
  }

  Widget _stepOne(Map<String, dynamic> method, String qrUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFDC2626)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Paid to', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    Text(
                      str(method['account_name'], method['name']),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(
                      'Rate: 1 RMB = ${ghsPerRmb.toStringAsFixed(4)} GHS · Min ¥${minRmb.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (qrUrl.isNotEmpty)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: qrUrl,
                height: 240,
                width: 240,
                fit: BoxFit.contain,
                placeholder: (_, _) => const SizedBox(
                  height: 240,
                  width: 240,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, _, _) => const Icon(Icons.qr_code_2, size: 120),
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Alipay QR is not available yet. Ask admin to upload it in Sell RMB settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red),
            ),
          ),
        if ((config['receive_instructions'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text('${config['receive_instructions']}', style: const TextStyle(color: Colors.black54, height: 1.35)),
        ],
      ],
    );
  }

  Widget _stepTwo() {
    final screenshotId = _fieldId('payment_screenshot');
    final picked = screenshotId == null ? null : files[screenshotId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'RMB amount sent *',
            prefixText: '¥ ',
            border: const OutlineInputBorder(),
            helperText: 'Minimum ¥${minRmb.toStringAsFixed(0)}',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You will receive: ${_ghs.format(ghsPayout)}',
          style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: alipayName,
          decoration: const InputDecoration(
            labelText: 'Your Alipay name (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Payment screenshot *', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            if (screenshotId == null) return;
            final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
            if (file != null) setState(() => files[screenshotId] = file);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: picked == null ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC), width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 40, color: picked == null ? Colors.grey : const Color(0xFF047857)),
                const SizedBox(height: 8),
                Text(
                  picked == null ? 'Tap to upload Alipay screenshot' : picked.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepThree() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Where should we send your GHS? Admin will send ${_ghs.format(ghsPayout)} after verifying your Alipay payment.',
            style: const TextStyle(height: 1.35),
          ),
        ),
        const SizedBox(height: 16),
        MomoNetworkPicker(
          value: momoNetwork,
          onChanged: (v) => setState(() => momoNetwork = v),
          selectedOnly: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: payoutMobile,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: '${momoNumberFieldLabel(momoNetwork, payoutMobile.text)} *',
            prefixIcon: const Icon(Icons.phone_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: payoutName,
          decoration: const InputDecoration(
            labelText: 'Name on MoMo account *',
            prefixIcon: Icon(Icons.person_outline),
            helperText: 'Must match the name on your mobile money wallet.',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  String str(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = '$value'.trim();
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    final method = selectedMethod;
    final qrUrl = ApiConfig.resolveMediaUrl(method?['qr_url'] as String?);
    final open = config['open'] == true || (config['open'] == null && config['enabled'] == true);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _popToChinaRmbHub(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Sell RMB for GHS'),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading…')
          : Column(
              children: [
                const SizedBox(height: 12),
                _stepDots(),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (error != null) ...[
                        Text(error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 8),
                      ],
                      if (step == 0 && method != null && open) _stepOne(method, qrUrl),
                      if (step == 0 && !open)
                        Text(
                          error ?? (config['status_message'] as String? ?? 'Sell RMB is not available right now.'),
                          style: const TextStyle(color: Colors.red, height: 1.35),
                        ),
                      if (step == 0 && open && method == null)
                        const Text(
                          'Alipay receive method is not configured yet.',
                          style: TextStyle(color: Colors.red, height: 1.35),
                        ),
                      if (step == 1) _stepTwo(),
                      if (step == 2) _stepThree(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Row(
                    children: [
                      if (step > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: submitting ? null : () => setState(() => step -= 1),
                            child: const Text('Back'),
                          ),
                        ),
                      if (step > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: submitting || !open || (step == 0 && qrUrl.isEmpty)
                              ? null
                              : () async {
                                  if (step < 2) {
                                    final validation = _validateStep(step + 1);
                                    if (validation != null) {
                                      setState(() => error = validation);
                                      return;
                                    }
                                    setState(() {
                                      error = null;
                                      step += 1;
                                    });
                                  } else {
                                    await _submit();
                                  }
                                },
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                          child: Text(
                            submitting
                                ? 'Submitting…'
                                : step == 2
                                    ? 'Submit'
                                    : 'Continue',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (step == 1)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Next: enter your Mobile Money details to receive GHS',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                if (step == 2)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Admin will verify your payment and send GHS to this MoMo number',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
              ],
            ),
    );
  }
}

class SellRmbShowScreen extends StatefulWidget {
  const SellRmbShowScreen({super.key, required this.id, this.initialTransfer});

  final int id;
  final Map<String, dynamic>? initialTransfer;

  @override
  State<SellRmbShowScreen> createState() => _SellRmbShowScreenState();
}

class _SellRmbShowScreenState extends State<SellRmbShowScreen> {
  Map<String, dynamic>? transfer;
  String? error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialTransfer != null) {
      transfer = Map<String, dynamic>.from(widget.initialTransfer!);
    }
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    final status = transfer?['status'] as String?;
    if (_sellTransferIsTerminal(status)) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (widget.id <= 0) {
      if (!mounted) return;
      setState(() => error = 'Invalid sell request.');
      return;
    }
    try {
      final data = await context.read<AppStore>().fetchSellRmb(widget.id);
      if (!mounted) return;
      setState(() {
        transfer = data;
        error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().trim();
      final friendly = message == 'Server Error' || message.contains('500')
          ? 'We received your sell request. Processing may take a moment — this page will refresh automatically.'
          : message;
      if (!silent || transfer == null) {
        setState(() => error = transfer == null ? friendly : null);
      }
      if (transfer != null && !_sellTransferIsTerminal(transfer?['status'] as String?)) {
        _schedulePoll();
      }
    }
  }

  bool get _isProcessing {
    final item = transfer;
    if (item == null) return true;
    if (item['processing'] == true) return true;
    return !_sellTransferIsTerminal(item['status'] as String?);
  }

  String get _processingTitle {
    final status = transfer?['status'] as String? ?? 'submitted';
    return switch (status) {
      'payout_processing' || 'paid' => 'Processing payout',
      'rmb_verification' || 'rmb_received' => 'Verifying payment',
      _ => 'Processing your sell',
    };
  }

  String get _processingSubtitle =>
      'Admin will verify your Alipay payment and send GHS to your MoMo number.';

  void _openImage(String url) {
    final resolved = ApiConfig.resolveMediaUrl(url);
    if (resolved.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: resolved,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _processingHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isProcessing
              ? const [Color(0xFF2563EB), Color(0xFF1D4ED8)]
              : const [Color(0xFF047857), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isProcessing)
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                Icon(
                  _isProcessing ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isProcessing ? _processingTitle : 'Payout complete',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            _isProcessing ? _processingSubtitle : 'GHS has been sent to your Mobile Money.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = transfer;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/wallet/china-rmb'),
          ),
          automaticallyImplyLeading: false,
          title: const Text('Sell RMB'),
        ),
        body: error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _processingHeader(),
                  const SizedBox(height: 16),
                  Text(error!, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              )
            : const FullPageLoader(label: 'Loading…'),
      );
    }

    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : <String, dynamic>{};
    final breakdown = quote['breakdown'] is Map ? Map<String, dynamic>.from(quote['breakdown'] as Map) : <String, dynamic>{};
    final timeline = (item['timeline'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final fields = (item['fields'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final proofs = (item['proofs'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((p) => p['type'] == 'payout_sent')
        .toList();
    final currency = (quote['payout_currency'] as String?) ?? 'ghs';
    final payout = currency == 'ghs'
        ? _ghs.format((quote['ghs_payout'] as num?)?.toDouble() ?? 0)
        : _usd.format((quote['usd_payout'] as num?)?.toDouble() ?? 0);
    final reference = '${item['reference'] ?? ''}';
    final status = '${item['status'] ?? ''}';
    final statusLabel = '${item['status_label'] ?? status}';
    final terminal = _sellTransferIsTerminal(status);
    final completed = status == 'completed';
    final rmbAmount = (quote['rmb_amount'] as num?)?.toDouble() ?? 0;
    final statusStyle = buyRmbTransferStatusStyle(item);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/wallet/china-rmb'),
        ),
        automaticallyImplyLeading: false,
        title: Text(reference),
        actions: [
          if (!terminal)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text('Auto refresh', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_isProcessing) ...[
              _processingHeader(),
              const SizedBox(height: 16),
            ],
            if (error != null && _isProcessing) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Text(error!, style: const TextStyle(fontSize: 13, height: 1.35)),
              ),
              const SizedBox(height: 12),
            ],
            if (!terminal && !_isProcessing)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    Icon(statusStyle.icon, color: statusStyle.color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: TextStyle(fontWeight: FontWeight.w800, color: statusStyle.color),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¥${rmbAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF047857)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expected payout: $payout',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  if (str(breakdown['rate']).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('${breakdown['rate']}', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                  if (completed) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Completed ${_formatSellWhen(item['completed_at'] as String?)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            ...timeline.map((step) {
              final current = step['current'] == true;
              final done = step['done'] == true;
              final failed = step['failed'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: current
                      ? const Color(0xFFECFDF5)
                      : done
                          ? const Color(0xFFF0FDF4)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: failed
                        ? const Color(0xFFFECACA)
                        : current
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      failed
                          ? Icons.cancel_rounded
                          : done
                              ? Icons.check_circle_rounded
                              : current
                                  ? Icons.hourglass_top_rounded
                                  : Icons.radio_button_unchecked,
                      color: failed
                          ? AppColors.danger
                          : done || current
                              ? const Color(0xFF047857)
                              : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${step['label']}',
                        style: TextStyle(
                          fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                          color: failed ? AppColors.danger : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if ((item['rejection_reason'] as String?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${item['rejection_reason']}', style: const TextStyle(color: Colors.red)),
              ),
            if (proofs.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Payout proof', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 8),
              ...proofs.map((proof) {
                final url = proof['url'] as String?;
                if (url == null || url.isEmpty) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${proof['original_name'] ?? 'Proof'}'),
                  );
                }
                return GestureDetector(
                  onTap: () => _openImage(url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: CachedNetworkImage(
                        imageUrl: ApiConfig.resolveMediaUrl(url),
                        fit: BoxFit.contain,
                        errorWidget: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
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
                        onTap: () => _openImage(url),
                        child: const Text(
                          'View file',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                        ),
                      )
                    : Text('${field['value'] ?? '—'}'),
              );
            }),
            if (item['can_cancel'] == true)
              TextButton(
                onPressed: () async {
                  await context.read<AppStore>().cancelSellRmb(widget.id);
                  await _load();
                },
                child: const Text('Cancel request'),
              ),
          ],
        ),
      ),
    );
  }
}

String str(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}
