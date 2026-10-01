import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/api_config.dart';
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
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> serviceTypes = [];
  double balance = 0;
  String query = '';
  String serviceType = '';
  String categoryId = '';

  List<Map<String, dynamic>> get _categories {
    if (serviceType.isEmpty) return groups;
    return groups.where((group) => '${group['service_type']}' == serviceType).toList();
  }

  List<Map<String, dynamic>> get _visibleGroups {
    final needle = query.trim().toLowerCase();
    return _categories.where((group) => categoryId.isEmpty || '${group['id']}' == categoryId).map((group) {
      final items = ((group['services'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((service) {
            final text = '${service['name']} ${service['description'] ?? ''} ${group['name']}'.toLowerCase();
            return needle.isEmpty || text.contains(needle);
          })
          .toList();
      return {...group, 'services': items};
    }).where((group) => (group['services'] as List).isNotEmpty).toList();
  }

  List<Map<String, dynamic>> get _ungrouped {
    final needle = query.trim().toLowerCase();
    return services.where((service) {
      if (service['group_id'] != null) return false;
      final typeOk = serviceType.isEmpty || '${service['service_type']}' == serviceType;
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
      final grp = data['groups'];
      final types = data['service_types'];
      final ord = data['orders'];
      final wallet = data['wallet'];
      setState(() {
        services = svc is List
            ? svc.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        groups = grp is List
            ? grp.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        serviceTypes = types is List
            ? types.map((e) => Map<String, dynamic>.from(e as Map)).toList()
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
        title: const Text('Place order', style: TextStyle(fontWeight: FontWeight.w900)),
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
                    'Instantly place orders using your wallet balance.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: serviceType.isEmpty ? '' : serviceType,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Select Type')),
                      ...serviceTypes.map(
                        (type) => DropdownMenuItem(value: '${type['value']}', child: Text('${type['label']}')),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      serviceType = value ?? '';
                      categoryId = '';
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: categoryId.isEmpty ? '' : categoryId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('All categories')),
                      ..._categories.map(
                        (group) => DropdownMenuItem(value: '${group['id']}', child: Text('${group['name']}')),
                      ),
                    ],
                    onChanged: (value) => setState(() => categoryId = value ?? ''),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search services...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      query = '';
                      serviceType = '';
                      categoryId = '';
                    }),
                    child: const Text('Reset'),
                  ),
                  const SizedBox(height: 14),
                  for (final group in _visibleGroups)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0F0F172A), blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                            child: Text(
                              '${group['name']}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFF3F4F6)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
                            child: Column(
                              children: [
                                for (final service in (group['services'] as List).cast<Map<String, dynamic>>())
                                  _GsmServiceRow(
                                    service: service,
                                    imageUrl: '${service['image_url'] ?? group['image_url'] ?? ''}',
                                    onTap: () => context.push('/gsm-tools/services/${service['id']}'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_ungrouped.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
                            child: Text(
                              'Other services',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFF3F4F6)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
                            child: Column(
                              children: [
                                for (final service in _ungrouped)
                                  _GsmServiceRow(
                                    service: service,
                                    imageUrl: '${service['image_url'] ?? ''}',
                                    onTap: () => context.push('/gsm-tools/services/${service['id']}'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_visibleGroups.every((g) => (g['services'] as List).isEmpty) && _ungrouped.isEmpty)
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
                        leading: GsmServiceLogo(url: '${order['image_url'] ?? ''}', size: 40),
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

class _GsmServiceRow extends StatelessWidget {
  const _GsmServiceRow({required this.service, required this.imageUrl, required this.onTap});

  final Map<String, dynamic> service;
  final String imageUrl;
  final VoidCallback onTap;

  String get _typeChip {
    final type = '${service['service_type'] ?? ''}'.toLowerCase();
    if (type == 'credit') return 'CREDIT';
    if (type.isEmpty) return 'GSM';
    return type.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final price = (service['price_ghs'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GsmServiceLogo(url: imageUrl, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${service['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25, color: Color(0xFF111827)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'GH₵${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _typeChip,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: Color(0xFFF97316)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
  final email = TextEditingController();
  int quantity = 1;

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
    email.dispose();
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
        quantity = (svc['min_qty'] as num?)?.toInt() ?? 1;
        email.text = '${data['contact_email'] ?? context.read<AppStore>().user?.email ?? ''}';
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
    final unit = (service!['price_ghs'] as num?)?.toDouble() ?? 0;
    final price = unit * quantity;
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
            quantity: quantity,
            email: email.text.trim(),
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
    final unit = (service?['price_ghs'] as num?)?.toDouble() ?? 0;
    final price = unit * quantity;
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
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 10),
                ],
                if ((service?['image_url'] ?? '').toString().isNotEmpty) ...[
                  Center(child: GsmServiceLogo(url: '${service!['image_url']}', size: 88)),
                  const SizedBox(height: 14),
                ],
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
                if (service?['allow_quantity'] == true)
                  Row(
                    children: [
                      const Text('Quantity *', style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          final min = (service?['min_qty'] as num?)?.toInt() ?? 1;
                          setState(() => quantity = quantity > min ? quantity - 1 : min);
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      IconButton(
                        onPressed: () {
                          final max = (service?['max_qty'] as num?)?.toInt() ?? 10;
                          setState(() => quantity = quantity < max ? quantity + 1 : max);
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
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
                  final isEmail = field['type'] == 'email' || name.toLowerCase() == 'email' || '${field['label']}'.toLowerCase() == 'email';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: controller,
                      obscureText: field['type'] == 'password',
                      keyboardType: field['type'] == 'number'
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : field['type'] == 'phone'
                              ? TextInputType.phone
                              : isEmail
                                  ? TextInputType.emailAddress
                                  : TextInputType.text,
                      maxLines: field['type'] == 'textarea' ? 3 : 1,
                      onChanged: isEmail ? (value) => email.text = value : null,
                      decoration: InputDecoration(
                        labelText: label,
                        hintText: field['placeholder']?.toString(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }),
                if (!fields.any((field) {
                  final name = '${field['name']}'.toLowerCase();
                  final label = '${field['label']}'.toLowerCase();
                  return field['type'] == 'email' || name == 'email' || label == 'email';
                }))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email*',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
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
                if ((service?['overview'] ?? service?['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Overview', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('${service!['overview'] ?? service!['description']}', style: const TextStyle(height: 1.4, color: AppColors.textSecondary)),
                ],
                if (((service?['features'] as List?) ?? []).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Key Features', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  ...((service!['features'] as List).map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $item'),
                      ))),
                ],
                if ((service?['what_to_send'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('What You Need To Send', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('${service!['what_to_send']}'),
                ],
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
                      GsmServiceLogo(url: '${order?['image_url'] ?? ''}', size: 52),
                      const SizedBox(width: 12),
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

class GsmServiceLogo extends StatelessWidget {
  const GsmServiceLogo({required this.url, this.size = 48});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.resolveMediaUrl(url);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      clipBehavior: Clip.antiAlias,
      child: resolved.isEmpty
          ? Center(
              child: Text(
                'GSM',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.22,
                  color: AppColors.primary,
                ),
              ),
            )
          : CachedNetworkImage(
              imageUrl: resolved,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) => Center(
                child: Text(
                  'GSM',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.22,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
    );
  }
}
