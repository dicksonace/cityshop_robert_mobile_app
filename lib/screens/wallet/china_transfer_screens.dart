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
  final amount = TextEditingController(text: '1000');

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

  Map<String, dynamic>? get rate => config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;

  @override
  Widget build(BuildContext context) {
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? 0;
    final rmbPerGhs = (rate?['rmb_per_ghs'] as num?)?.toDouble() ?? 0;
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    final send = double.tryParse(amount.text) ?? 0;
    final rmb = ghsPerRmb > 0 ? send / ghsPerRmb : 0.0;
    final fee = feeMode == 'percent' ? send * feeValue / 100 : feeValue;
    final enabled = config['enabled'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer to China')),
      body: loading
          ? const FullPageLoader(label: 'Loading rates…')
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
                        colors: [Color(0xFF5B21B6), Color(0xFF6D28D9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current Exchange Rates', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('GHS to RMB · Alipay only', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        const SizedBox(height: 16),
                        Text(
                          rate == null ? 'Rate not published yet' : '1 GHS → ${rmbPerGhs.toStringAsFixed(3)} RMB',
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                        ),
                        if (rate != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('1 RMB = GH₵${ghsPerRmb.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white70)),
                          ),
                      ],
                    ),
                  ),
                  if ((config['instructions'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text('${config['instructions']}', style: const TextStyle(color: Color(0xFF9A3412))),
                  ],
                  if (rate != null) ...[
                    const SizedBox(height: 18),
                    const Text('Amount to send (GHS)', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    _row('RMB value', '¥${rmb.toStringAsFixed(2)}'),
                    _row('Transfer fee', _ghs.format(fee)),
                    _row('Total payment', _ghs.format(send + fee), bold: true),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: enabled
                          ? () => context.push('/wallet/china-transfer/create', extra: amount.text)
                          : null,
                      child: Text(enabled ? 'Continue to Alipay details' : 'Transfers paused'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const Text('Your transfers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (transfers.isEmpty) const Text('No China transfers yet.', style: TextStyle(color: Colors.black54)),
                  ...transfers.map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        '${_ghs.format((quote['total_payable_ghs'] as num?)?.toDouble() ?? 0)} → ¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      ),
                      trailing: Text('${item['status_label']}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                      onTap: () => context.push('/wallet/china-transfer/${item['id']}'),
                    );
                  }),
                ],
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
  int? methodId;
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
      final data = await context.read<AppStore>().loadChinaTransfers();
      if (!mounted) return;
      final cfg = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      final methods = (cfg['payment_methods'] as List? ?? []).whereType<Map>().toList();
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

  List<Map<String, dynamic>> get methods => (config['payment_methods'] as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  Future<void> _submit() async {
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final created = await context.read<AppStore>().submitChinaTransfer(
            ghsAmount: amount.text,
            paymentMethodId: methodId ?? 0,
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
    final rate = config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? 0;
    final send = double.tryParse(amount.text) ?? 0;
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    final rmb = ghsPerRmb > 0 ? send / ghsPerRmb : 0.0;
    final fee = feeMode == 'percent' ? send * feeValue / 100 : feeValue;

    return Scaffold(
      appBar: AppBar(title: const Text('Send via Alipay')),
      body: loading
          ? const FullPageLoader(label: 'Loading form…')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                const Text('Amount to send (GHS)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Text('Exchange rate: 1 RMB = GH₵${ghsPerRmb.toStringAsFixed(4)}'),
                Text('RMB value: ¥${rmb.toStringAsFixed(2)}'),
                Text('Transfer fee: ${_ghs.format(fee)}'),
                Text('Total payment: ${_ghs.format(send + fee)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                const Text('Alipay recipient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ...fields.where((f) => f['group'] == 'recipient').map(_field),
                const SizedBox(height: 20),
                const Text('Pay GHS to CityShop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ...methods.map((method) {
                  final id = (method['id'] as num).toInt();
                  return RadioListTile<int>(
                    value: id,
                    groupValue: methodId,
                    onChanged: (v) => setState(() => methodId = v),
                    title: Text('${method['name']}'),
                    subtitle: Text(
                      [method['account_name'], method['account_number']].where((e) => (e as String?)?.isNotEmpty == true).join(' · '),
                    ),
                  );
                }),
                ...fields.where((f) => f['group'] == 'payment').map(_field),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submitting ? null : _submit,
                  child: Text(submitting ? 'Submitting…' : 'Submit transfer'),
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
            const SizedBox(height: 12),
            Text('GHS paid: ${_ghs.format((quote['total_payable_ghs'] as num?)?.toDouble() ?? 0)}'),
            Text('Exchange rate: 1 RMB = GH₵${((quote['ghs_per_rmb'] as num?)?.toDouble() ?? 0).toStringAsFixed(4)}'),
            Text('RMB amount: ¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
            Text('Fee: ${_ghs.format((quote['fee_ghs'] as num?)?.toDouble() ?? 0)}'),
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
