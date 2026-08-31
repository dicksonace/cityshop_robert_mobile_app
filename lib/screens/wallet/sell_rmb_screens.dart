import 'dart:async';
import 'dart:io';

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

String _formatSellFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

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
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF6EE7B7)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.payments_outlined, color: Color(0xFF047857), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'You receive (GHS)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: Color(0xFF047857),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              rmb > 0 ? _ghs.format(ghsPayout) : 'GH₵0.00',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF065F46),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              rmb > 0
                                  ? 'Estimated MoMo payout for ¥${rmb.toStringAsFixed(rmb == rmb.roundToDouble() ? 0 : 2)}'
                                  : 'Enter RMB above to see your GHS payout',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.35),
                            ),
                          ],
                        ),
                      ),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF6EE7B7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You receive (GHS)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF047857)),
              ),
              const SizedBox(height: 4),
              Text(
                _ghs.format(ghsPayout),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF065F46)),
              ),
            ],
          ),
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
        _SellPaymentScreenshotCard(
          file: picked,
          onPick: () async {
            if (screenshotId == null) return;
            final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
            if (file != null) setState(() => files[screenshotId] = file);
          },
          onClear: screenshotId == null || picked == null
              ? null
              : () => setState(() => files.remove(screenshotId)),
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
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (step == 1)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Next: enter your Mobile Money details to receive GHS',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                        if (step == 2)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Admin will verify your payment and send GHS to this MoMo number',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                        Row(
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Sell payment screenshot: green check + size + Change / X + image preview.
class _SellPaymentScreenshotCard extends StatelessWidget {
  const _SellPaymentScreenshotCard({
    required this.file,
    required this.onPick,
    this.onClear,
  });

  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  Future<void> _openPreview(BuildContext context) async {
    if (file == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(File(file!.path), fit: BoxFit.contain),
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

  @override
  Widget build(BuildContext context) {
    final picked = file != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Payment screenshot',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black),
              ),
              TextSpan(
                text: ' *',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFDC2626)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Upload a clear Alipay payment screenshot so admin can verify.',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: picked ? const Color(0xFFECFDF5) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
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
                                    size == null ? '…' : _formatSellFileSize(size),
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
                      'Tap image to view full size',
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
                        Icon(Icons.image_outlined, size: 40, color: Colors.grey.shade500),
                        const SizedBox(height: 10),
                        const Text(
                          'Upload Alipay payment screenshot',
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

  String _fieldValue(List<Map<String, dynamic>> fields, String name) {
    for (final field in fields) {
      if (field['name'] == name) {
        return str(field['value']);
      }
    }
    return '';
  }

  Map<String, dynamic> _presentation(Map<String, dynamic> item) {
    final raw = item['status_presentation'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final status = str(item['status'], 'submitted');
    return switch (status) {
      'payout_processing' || 'paid' => {
          'header_title': 'Processing Payout',
          'header_subtitle': 'Admin is sending GHS to your MoMo',
          'header_color': '#3b82f6',
          'badge_label': 'Processing',
        },
      'completed' => {
          'header_title': 'Payout Complete!',
          'header_subtitle': 'GHS has been sent to your Mobile Money',
          'header_color': '#22c55e',
          'badge_label': 'Completed',
        },
      'rejected' || 'failed' => {
          'header_title': 'Sell Request Rejected',
          'header_subtitle': 'See details below',
          'header_color': '#dc2626',
          'badge_label': 'Rejected',
        },
      _ => {
          'header_title': 'Awaiting Review',
          'header_subtitle': 'Your RMB sell is being verified',
          'header_color': '#ef4444',
          'badge_label': 'Pending',
        },
    };
  }

  Map<String, String> _payoutAccount(Map<String, dynamic> item, List<Map<String, dynamic>> fields) {
    final raw = item['payout_account'];
    if (raw is Map) {
      return {
        'network': str(raw['network'], '—'),
        'number': str(raw['number'], '—'),
        'account_name': str(raw['account_name'], '—'),
      };
    }
    return {
      'network': _fieldValue(fields, 'payout_bank_name').isEmpty ? '—' : _fieldValue(fields, 'payout_bank_name'),
      'number': () {
        final mobile = _fieldValue(fields, 'payout_mobile');
        if (mobile.isNotEmpty) return mobile;
        return _fieldValue(fields, 'payout_account_number').isEmpty ? '—' : _fieldValue(fields, 'payout_account_number');
      }(),
      'account_name': _fieldValue(fields, 'payout_name').isEmpty ? '—' : _fieldValue(fields, 'payout_name'),
    };
  }

  Color _hexColor(String hex, {Color fallback = const Color(0xFFEF4444)}) {
    final value = hex.replaceAll('#', '');
    if (value.length != 6) return fallback;
    return Color(int.parse('FF$value', radix: 16));
  }

  Widget _statusHeader(Map<String, dynamic> presentation, {required bool completed, required bool rejected, required bool processing}) {
    final color = _hexColor(str(presentation['header_color'], '#ef4444'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      decoration: BoxDecoration(color: color),
      child: Column(
        children: [
          if (completed)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 48),
            )
          else if (rejected)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.cancel, color: Colors.white, size: 48),
            )
          else
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  const SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            str(presentation['header_title'], 'Awaiting Review'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
          ),
          const SizedBox(height: 6),
          Text(
            str(presentation['header_subtitle'], 'Your RMB sell is being verified'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required double rmbAmount,
    required double ghsPerRmb,
    required String youReceive,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFEE2E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SELL SUMMARY',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C), letterSpacing: 0.6),
          ),
          const SizedBox(height: 10),
          _summaryRow('RMB Sent', '¥ ${rmbAmount.toStringAsFixed(2)}', valueColor: const Color(0xFFDC2626), valueSize: 20),
          const SizedBox(height: 8),
          _summaryRow('Rate', '1 RMB = ${ghsPerRmb.toStringAsFixed(4)} GHS'),
          const Divider(height: 20, color: Color(0xFFFEE2E2)),
          _summaryRow('You Receive', youReceive, valueColor: const Color(0xFF16A34A), valueSize: 20, bold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? valueColor, double valueSize = 14, bool bold = false}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 14))),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? const Color(0xFF1F2937),
            fontSize: valueSize,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _payoutCard(Map<String, String> payout) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCFCE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PAYOUT ACCOUNT (MOMO)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF166534), letterSpacing: 0.6),
          ),
          const SizedBox(height: 10),
          _summaryRow('Network', payout['network'] ?? '—'),
          const SizedBox(height: 8),
          _summaryRow('Number', payout['number'] ?? '—'),
          const SizedBox(height: 8),
          _summaryRow('Account Name', payout['account_name'] ?? '—'),
        ],
      ),
    );
  }

  Widget _detailsCard({
    required String reference,
    required int id,
    required String submitted,
    required String badgeLabel,
    required Color badgeColor,
    required Color badgeTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _summaryRow('Reference', reference),
          const SizedBox(height: 8),
          _summaryRow('Request ID', '#$id'),
          const SizedBox(height: 8),
          _summaryRow('Submitted', submitted),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Status', style: TextStyle(color: Color(0xFF6B7280), fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(color: badgeTextColor, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  (Color bg, Color text) _badgeColors(String status) {
    return switch (status) {
      'payout_processing' || 'paid' => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
      'completed' => (const Color(0xFFD1FAE5), const Color(0xFF047857)),
      'rejected' || 'failed' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      'cancelled' => (const Color(0xFFF3F4F6), const Color(0xFF374151)),
      _ => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
    };
  }

  Widget _statusBody(Map<String, dynamic> item) {
    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : <String, dynamic>{};
    final fields = (item['fields'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final proofs = (item['proofs'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((p) => p['type'] == 'payout_sent')
        .toList();
    final presentation = _presentation(item);
    final payout = _payoutAccount(item, fields);
    final status = str(item['status']);
    final completed = status == 'completed';
    final rejected = status == 'rejected' || status == 'failed';
    final processing = _isProcessing;
    final currency = str(quote['payout_currency'], 'ghs');
    final youReceive = currency == 'ghs'
        ? _ghs.format((quote['ghs_payout'] as num?)?.toDouble() ?? 0)
        : _usd.format((quote['usd_payout'] as num?)?.toDouble() ?? 0);
    final ghsPerRmb = (quote['ghs_per_rmb'] as num?)?.toDouble() ??
        (((quote['usd_per_rmb'] as num?)?.toDouble() ?? 0) * ((quote['ghs_per_usd'] as num?)?.toDouble() ?? 0));
    final rmbAmount = (quote['rmb_amount'] as num?)?.toDouble() ?? 0;
    final badge = _badgeColors(status);
    final badgeLabel = str(presentation['badge_label'], str(item['status_label'], status));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shadowColor: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusHeader(presentation, completed: completed, rejected: rejected, processing: processing),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryCard(rmbAmount: rmbAmount, ghsPerRmb: ghsPerRmb, youReceive: youReceive),
                const SizedBox(height: 14),
                _payoutCard(payout),
                const SizedBox(height: 14),
                _detailsCard(
                  reference: str(item['reference'], '#${item['id']}'),
                  id: item['id'] as int? ?? widget.id,
                  submitted: _formatSellWhen(item['submitted_at'] as String? ?? item['created_at'] as String?),
                  badgeLabel: badgeLabel,
                  badgeColor: badge.$1,
                  badgeTextColor: badge.$2,
                ),
                if ((item['rejection_reason'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: Colors.red.shade400, width: 4)),
                    ),
                    child: Text('${item['rejection_reason']}', style: const TextStyle(color: Color(0xFFB91C1C), height: 1.35)),
                  ),
                ],
                if (completed && proofs.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('MoMo Payment Proof', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF166534))),
                  const SizedBox(height: 8),
                  ...proofs.map((proof) {
                    final url = proof['url'] as String?;
                    if (url == null || url.isEmpty) return const SizedBox.shrink();
                    return GestureDetector(
                      onTap: () => _openImage(url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: ApiConfig.resolveMediaUrl(url),
                          fit: BoxFit.contain,
                          errorWidget: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                    );
                  }),
                ],
                if (completed) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: Colors.green.shade400, width: 4)),
                    ),
                    child: Text(
                      '$youReceive was sent to your ${payout['network']} account.',
                      style: const TextStyle(color: Color(0xFF166534), height: 1.35),
                    ),
                  ),
                ],
                if (processing) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Status updates automatically every few seconds.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap Refresh below or return to your wallet anytime.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                ],
                if (error != null && processing) ...[
                  const SizedBox(height: 12),
                  Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF1D4ED8), fontSize: 13, height: 1.35)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _load,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Refresh'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context.go('/wallet/china-rmb'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Back to Wallet'),
                      ),
                    ),
                  ],
                ),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = transfer;
    final terminal = item != null && _sellTransferIsTerminal(item['status'] as String?);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/wallet/china-rmb'),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Sell RMB'),
        actions: [
          if (item != null && !terminal)
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
            if (item == null)
              (widget.initialTransfer != null || error != null)
                  ? _statusBody({
                      'id': widget.id,
                      'reference': str(widget.initialTransfer?['reference'], 'Sell RMB'),
                      'status': str(widget.initialTransfer?['status'], 'submitted'),
                      'quote': widget.initialTransfer?['quote'] ?? {},
                      'fields': widget.initialTransfer?['fields'] ?? [],
                      'payout_account': widget.initialTransfer?['payout_account'],
                      'status_presentation': widget.initialTransfer?['status_presentation'],
                      'can_cancel': widget.initialTransfer?['can_cancel'] == true,
                    })
                  : const FullPageLoader(label: 'Loading…')
            else
              _statusBody(item),
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
