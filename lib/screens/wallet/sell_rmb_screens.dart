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
    final enabled = config['enabled'] == true;

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
                        onPressed: enabled
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
                        child: Text(enabled ? 'Continue' : 'Sell RMB paused'),
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
  final amount = TextEditingController();
  int? methodId;
  final values = <int, String>{};
  final files = <int, XFile>{};

  @override
  void initState() {
    super.initState();
    amount.text = widget.initialRmb ?? '10000';
    _load();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppStore>().loadSellRmb();
      if (!mounted) return;
      final cfg = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      final methods = (cfg['receive_methods'] as List? ?? []).whereType<Map>().toList();
      setState(() {
        config = cfg;
        methodId = methods.isEmpty ? null : (methods.first['id'] as num?)?.toInt();
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

  Future<void> _submit() async {
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
      context.go('/wallet/sell-rmb/${created['id']}');
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
    final rate = config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;
    final usdPerRmb = (rate?['usd_per_rmb'] as num?)?.toDouble() ?? 0;
    final ghsPerUsd = (rate?['ghs_per_usd'] as num?)?.toDouble() ?? 0;
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? (usdPerRmb * ghsPerUsd);
    final rmb = double.tryParse(amount.text) ?? 0;
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    final usdGross = usdPerRmb > 0 ? rmb * usdPerRmb : 0.0;
    final fee = feeMode == 'percent' ? usdGross * feeValue / 100 : feeValue;
    final ghsGross = rmb * ghsPerRmb;
    final feeGhs = usdGross > 0 ? ghsGross * (fee / usdGross) : 0.0;
    final ghsPayout = ghsGross - feeGhs;
    Map<String, dynamic>? selectedMethod;
    for (final m in methods) {
      if ((m['id'] as num?)?.toInt() == methodId) {
        selectedMethod = m;
        break;
      }
    }
    selectedMethod ??= methods.isEmpty ? null : methods.first;
    final qrUrl = (selectedMethod?['qr_url'] as String?)?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _popToChinaRmbHub(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Sell RMB details'),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading form…')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                const Text('RMB amount', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixText: '¥ ', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Text('Buying rate: 1 RMB = GH₵${ghsPerRmb.toStringAsFixed(4)}'),
                Text('You receive: ${_ghs.format(ghsPayout)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Send RMB to our Alipay QR. After you upload proof, admin verifies and processes your GHS payout.',
                  style: TextStyle(color: Colors.black54, height: 1.35),
                ),
                if ((config['receive_instructions'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('${config['receive_instructions']}', style: const TextStyle(color: Colors.black54)),
                ],
                const SizedBox(height: 16),
                const Text('Send RMB to CityShop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ...methods.map((method) {
                  final id = (method['id'] as num).toInt();
                  return RadioListTile<int>(
                    value: id,
                    groupValue: methodId,
                    onChanged: (v) => setState(() => methodId = v),
                    title: Text('${method['name']}'),
                    subtitle: Text(
                      [
                        method['type'],
                        method['account_name'],
                        method['account_number'],
                      ].where((e) => (e as String?)?.isNotEmpty == true).join(' · '),
                    ),
                  );
                }),
                if (qrUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        const Text('Pay Alipay', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text(
                          'Scan the QR code to transfer RMB to our account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            qrUrl,
                            height: 220,
                            width: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(Icons.qr_code_2, size: 80),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ...fields.where((f) => f['group'] == 'payment').map(_field),
                const SizedBox(height: 16),
                const Text('Your payout details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ...fields.where((f) => f['group'] == 'payout' || f['group'] == 'recipient').map(_field),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submitting ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                  child: Text(submitting ? 'Submitting…' : 'Submit Sell RMB'),
                ),
              ],
            ),
    );
  }

  Widget _field(Map<String, dynamic> field) {
    final id = (field['id'] as num).toInt();
    final type = field['type'] as String? ?? 'text';
    final label = '${field['label']}${field['required'] == true ? ' *' : ''}';
    if (['image', 'document', 'files'].contains(type)) {
      final picked = files[id];
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((field['help_text'] as String?)?.isNotEmpty == true)
              Text('${field['help_text']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            TextButton(
              onPressed: () async {
                final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (file != null) setState(() => files[id] = file);
              },
              child: Text(picked == null ? 'Choose file' : picked.name),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        minLines: type == 'textarea' ? 3 : 1,
        maxLines: type == 'textarea' ? 5 : 1,
        keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
        onChanged: (v) => values[id] = v,
        decoration: InputDecoration(
          labelText: label,
          hintText: field['placeholder'] as String?,
          helperText: field['help_text'] as String?,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class SellRmbShowScreen extends StatefulWidget {
  const SellRmbShowScreen({super.key, required this.id});

  final int id;

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
      if (!silent) setState(() => error = e.toString());
    }
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
        body: error != null ? Center(child: Text(error!)) : const FullPageLoader(label: 'Loading…'),
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
            if (!terminal)
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
