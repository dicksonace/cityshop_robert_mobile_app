import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/payment_pin_sheet.dart';

class GsmToolsHubScreen extends StatefulWidget {
  const GsmToolsHubScreen({super.key});

  @override
  State<GsmToolsHubScreen> createState() => _GsmToolsHubScreenState();
}

class _GsmToolsHubScreenState extends State<GsmToolsHubScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> services = [];
  List<Map<String, dynamic>> orders = [];
  double balance = 0;
  String query = '';
  String serviceType = 'all';

  static const _types = <(String, String)>[
    ('all', 'All services'),
    ('imei', 'IMEI Service'),
    ('server', 'Server Service'),
    ('remote', 'Remote Service'),
    ('file', 'File Service'),
  ];

  List<Map<String, dynamic>> get _visible {
    final needle = query.trim().toLowerCase();
    return services.where((service) {
      final type = '${service['service_type'] ?? 'imei'}';
      final typeOk = serviceType == 'all' || type == serviceType;
      final text = '${service['name']} ${service['description'] ?? ''}'.toLowerCase();
      return typeOk && (needle.isEmpty || text.contains(needle));
    }).toList();
  }

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
      final data = await context.read<AppStore>().loadGsmTools();
      if (!mounted) return;
      final svc = data['services'];
      final ord = data['orders'];
      final wallet = data['wallet'];
      setState(() {
        services = svc is List
            ? svc.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        orders = ord is List
            ? ord.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        balance = (wallet is Map ? (wallet['available_balance'] as num?)?.toDouble() : null) ?? 0;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not load GSM Tools.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('GSM Tools', style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Text(
                    'Balance GH₵${balance.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.emerald),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Unlock & device services — paid from your wallet.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search services',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: serviceType,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _types
                        .map((type) => DropdownMenuItem(value: type.$1, child: Text(type.$2)))
                        .toList(),
                    onChanged: (value) => setState(() => serviceType = value ?? 'all'),
                  ),
                  const SizedBox(height: 14),
                  ..._visible.map((service) {
                    final price = (service['price_ghs'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => context.push('/gsm-tools/services/${service['id']}'),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFDBA74)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${service['name']}',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                      ),
                                      Text(
                                        '${service['service_type_label'] ?? 'IMEI Service'}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                                      ),
                                      if ((service['description'] ?? '').toString().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '${service['description']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Text(
                                  'GH₵${price.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No GSM services available yet.', textAlign: TextAlign.center),
                    ),
                  if (orders.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text('My orders', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    ...orders.map((order) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${order['service_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${order['reference']}'),
                        trailing: Text(
                          '${order['status_label']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: order['status'] == 'processing'
                                ? const Color(0xFF1D4ED8)
                                : order['status'] == 'completed'
                                    ? const Color(0xFF047857)
                                    : AppColors.primary,
                          ),
                        ),
                        onTap: () => context.push('/gsm-tools/orders/${order['id']}'),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}

class GsmToolOrderScreen extends StatefulWidget {
  const GsmToolOrderScreen({super.key, required this.serviceId});
  final int serviceId;

  @override
  State<GsmToolOrderScreen> createState() => _GsmToolOrderScreenState();
}

class _GsmToolOrderScreenState extends State<GsmToolOrderScreen> {
  bool loading = true;
  bool submitting = false;
  String? error;
  Map<String, dynamic>? service;
  double balance = 0;
  bool hasPin = false;
  final Map<String, TextEditingController> fieldControllers = {};
  final Map<String, String> imagePaths = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().fetchGsmService(widget.serviceId);
      final svc = Map<String, dynamic>.from(data['service'] as Map);
      final fields = (svc['fields'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final f in fields) {
        if (f['type'] == 'image') continue;
        fieldControllers['${f['name']}'] = TextEditingController();
      }
      final wallet = data['wallet'];
      setState(() {
        service = svc;
        balance = (wallet is Map ? (wallet['available_balance'] as num?)?.toDouble() : null) ?? 0;
        hasPin = data['has_payment_pin'] == true;
        loading = false;
      });
    } catch (_) {
      setState(() {
        loading = false;
        error = 'Could not load service.';
      });
    }
  }

  Future<void> _submit() async {
    if (service == null || submitting) return;
    final store = context.read<AppStore>();
    final price = (service!['price_ghs'] as num?)?.toDouble() ?? 0;
    if (!(store.user?.canStoreWalletFunds ?? false)) {
      setState(() => error = 'Approve your Ghana Card (KYC) before placing GSM orders.');
      return;
    }
    if (balance < price) {
      setState(() => error = "You don't have enough balance. Please top up your wallet.");
      return;
    }
    if (!hasPin) {
      setState(() => error = 'Set a payment PIN in your account first.');
      return;
    }
    final fields = <String, String>{};
    for (final entry in fieldControllers.entries) {
      fields[entry.key] = entry.value.text.trim();
    }
    final defs = (service!['fields'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map));
    for (final field in defs) {
      if (field['type'] == 'image' && field['required'] == true && (imagePaths['${field['name']}'] ?? '').isEmpty) {
        setState(() => error = 'Add ${field['label']}.');
        return;
      }
    }
    final pin = await promptPaymentPin(
      context,
      title: 'Confirm GSM order',
      subtitle: 'Authorize this wallet payment with your PIN',
    );
    if (pin == null || !mounted) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final created = await store.submitGsmOrder(
            serviceId: widget.serviceId,
            fields: fields,
            files: imagePaths,
            paymentPin: pin,
          );
      final order = created['order'];
      final id = order is Map ? order['id'] : null;
      if (!mounted) return;
      if (id != null) {
        context.go('/gsm-tools/orders/$id');
      } else {
        context.go('/gsm-tools');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = (service?['price_ghs'] as num?)?.toDouble() ?? 0;
    final fields = (service?['fields'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final enough = balance >= price;
    final kycOk = context.watch<AppStore>().user?.canStoreWalletFunds ?? false;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(service?['name']?.toString() ?? 'GSM Tool', style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if ((service?['description'] ?? '').toString().isNotEmpty)
                  Text('${service!['description']}', style: const TextStyle(height: 1.4, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                Text(
                  'Total GH₵${price.toStringAsFixed(2)} — deducted from your wallet.',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('Balance GH₵${balance.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textSecondary)),
                if (!enough)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Text("You don't have enough balance. Please top up your wallet."),
                  ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                ...fields.map((field) {
                  final name = '${field['name']}';
                  final label = '${field['label']}${field['required'] == true ? '*' : ''}';
                  if (field['type'] == 'image') {
                    final path = imagePaths[name];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
                          if (picked == null) return;
                          setState(() => imagePaths[name] = picked.path);
                        },
                        icon: const Icon(Icons.photo_outlined),
                        label: Text(path == null ? label : '$label added'),
                      ),
                    );
                  }
                  final controller = fieldControllers[name]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: controller,
                      keyboardType: field['type'] == 'number'
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : field['type'] == 'phone'
                              ? TextInputType.phone
                              : TextInputType.text,
                      maxLines: field['type'] == 'textarea' ? 3 : 1,
                      decoration: InputDecoration(
                        labelText: label,
                        hintText: field['placeholder']?.toString(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }),
                if (!kycOk)
                  TextButton(
                    onPressed: () => context.push('/kyc'),
                    child: const Text('Approve Ghana Card (KYC) before placing GSM orders.'),
                  ),
                if (!hasPin)
                  TextButton(
                    onPressed: () => context.push('/profile/payment-pin'),
                    child: const Text('Set a payment PIN before placing GSM orders.'),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submitting || !enough || !hasPin || !kycOk ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(submitting ? 'Placing…' : 'Place Order', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
    );
  }
}

class GsmToolShowScreen extends StatefulWidget {
  const GsmToolShowScreen({super.key, required this.id});
  final int id;

  @override
  State<GsmToolShowScreen> createState() => _GsmToolShowScreenState();
}

class _GsmToolShowScreenState extends State<GsmToolShowScreen> {
  bool loading = true;
  Map<String, dynamic>? order;
  String? error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPoll() {
    _poll?.cancel();
    final status = '${order?['status'] ?? ''}';
    if (status == 'pending' || status == 'processing') {
      _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await context.read<AppStore>().fetchGsmOrder(widget.id);
      if (!mounted) return;
      setState(() {
        order = Map<String, dynamic>.from(data['order'] as Map);
        loading = false;
      });
      _syncPoll();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        if (!silent) error = 'Could not load order.';
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'processing':
        return const Color(0xFF1D4ED8);
      case 'completed':
        return const Color(0xFF047857);
      case 'failed':
      case 'cancelled':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFFB45309);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: const Text('Funds will return to your wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final data = await context.read<AppStore>().cancelGsmOrder(widget.id);
      setState(() => order = Map<String, dynamic>.from(data['order'] as Map));
      _syncPoll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancelled. Wallet refunded.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = (order?['fields'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final replies = (order?['replies'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final price = (order?['price_ghs'] as num?)?.toDouble() ?? 0;
    final status = '${order?['status'] ?? ''}';
    final resultNote = '${order?['admin_result_note'] ?? ''}';

    return Scaffold(
      appBar: AppBar(
        title: Text(order?['reference']?.toString() ?? 'GSM order', style: const TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/gsm-tools'),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text('${order?['service_name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${order?['status_label'] ?? status}'.toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: _statusColor(status)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Paid GH₵${price.toStringAsFixed(2)}'),
                  if (status == 'processing')
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Processing — the admin reply will appear below.', style: TextStyle(color: Color(0xFF1D4ED8))),
                    ),
                  if (status == 'pending')
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Pending — waiting for admin to start Processing.', style: TextStyle(color: Color(0xFFB45309))),
                    ),
                  const SizedBox(height: 16),
                  ...fields.map((f) {
                    final value = '${f['value'] ?? ''}';
                    final image = f['type'] == 'image' && value.startsWith('http');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${f['label']}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                          if (image)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(value, height: 180, fit: BoxFit.cover),
                              ),
                            )
                          else
                            Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const Text('Admin reply', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  if (replies.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        resultNote.isNotEmpty
                            ? resultNote
                            : 'No reply yet. Status will move to Processing, then Completed.',
                      ),
                    )
                  else
                    ...replies.map(
                      (reply) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${reply['body'] ?? ''}'),
                            const SizedBox(height: 4),
                            Text(
                              '${reply['admin'] ?? 'Admin'}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if ((order?['failure_reason'] ?? '').toString().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                      child: Text('${order!['failure_reason']}'),
                    ),
                  if (order?['can_cancel'] == true) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: _cancel, child: const Text('Cancel & refund')),
                  ],
                ],
              ),
            ),
    );
  }
}
