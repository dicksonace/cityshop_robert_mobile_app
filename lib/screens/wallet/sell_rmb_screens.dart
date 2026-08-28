import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _usd = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

void _popToChinaRmbHub(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/wallet/china-rmb');
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => _popToChinaRmbHub(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Sell RMB'),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading buying rate…')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
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
                              if (mounted) _load();
                            }
                          : null,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                      child: Text(enabled ? 'Continue' : 'Sell RMB paused'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const Text('Your Sell RMB requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (transfers.isEmpty)
                    const Text('No Sell RMB requests yet.', style: TextStyle(color: Colors.black54)),
                  ...transfers.map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    final currency = (quote['payout_currency'] as String?) ?? 'ghs';
                    final payout = currency == 'ghs'
                        ? _ghs.format((quote['ghs_payout'] as num?)?.toDouble() ?? 0)
                        : _usd.format((quote['usd_payout'] as num?)?.toDouble() ?? 0);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        '¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} → $payout',
                      ),
                      trailing: Text(
                        '${item['status_label']}',
                        style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w700),
                      ),
                      onTap: () async {
                        await context.push('/wallet/sell-rmb/${item['id']}');
                        if (mounted) _load();
                      },
                    );
                  }),
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
                  'Send RMB to our Alipay QR (no RMB wallet). After you upload proof, admin processes your GHS payout.',
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
                            errorBuilder: (_, __, ___) => const Icon(Icons.qr_code_2, size: 80),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppStore>().fetchSellRmb(widget.id);
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
    final timeline = (item['timeline'] as List? ?? []).whereType<Map>().toList();
    final fields = (item['fields'] as List? ?? []).whereType<Map>().toList();
    final proofs = (item['proofs'] as List? ?? [])
        .whereType<Map>()
        .where((p) => p['type'] == 'payout_sent')
        .toList();
    final currency = (quote['payout_currency'] as String?) ?? 'ghs';
    final payout = currency == 'ghs'
        ? _ghs.format((quote['ghs_payout'] as num?)?.toDouble() ?? 0)
        : _usd.format((quote['usd_payout'] as num?)?.toDouble() ?? 0);
    final ghsPerRmb = (quote['ghs_per_rmb'] as num?)?.toDouble() ??
        (((quote['usd_per_rmb'] as num?)?.toDouble() ?? 0) *
            ((quote['ghs_per_usd'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/wallet/china-rmb'),
        ),
        automaticallyImplyLeading: false,
        title: Text('${item['reference']}'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              '${item['status_label']}',
              style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text('RMB sold: ¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
            Text('Buying rate: 1 RMB = GH₵${ghsPerRmb.toStringAsFixed(4)}'),
            Text('Expected payout: $payout'),
            if (item['payout_amount'] != null)
              Text(
                'Paid: ${currency == 'ghs' ? _ghs.format((item['payout_amount'] as num).toDouble()) : _usd.format((item['payout_amount'] as num).toDouble())}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 20),
            ...timeline.map((step) {
              final current = step['current'] == true;
              final done = step['done'] == true;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  current
                      ? Icons.radio_button_checked
                      : done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                  color: current
                      ? const Color(0xFF047857)
                      : done
                          ? Colors.green
                          : Colors.grey,
                ),
                title: Text(
                  '${step['label']}',
                  style: TextStyle(fontWeight: current ? FontWeight.w800 : FontWeight.w500),
                ),
              );
            }),
            if ((item['rejection_reason'] as String?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('${item['rejection_reason']}', style: const TextStyle(color: Colors.red)),
              ),
            if (proofs.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Payout proof', style: TextStyle(fontWeight: FontWeight.w800)),
              ...proofs.map((proof) {
                final url = proof['url'] as String?;
                return TextButton(
                  onPressed: url == null
                      ? null
                      : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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
