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
        actions: [
          TextButton(
            onPressed: () => context.push('/gsm-tools/history'),
            child: const Text(
              'Order History',
              style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFEA580C)),
            ),
          ),
        ],
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: const [BoxShadow(color: Color(0x33EA580C), blurRadius: 16, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('WALLET BALANCE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
                        const SizedBox(height: 4),
                        Text(
                          'GH₵${balance.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Place orders instantly from your wallet.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
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
                ],
              ),
            ),
    );
  }
}

class GsmToolsHistoryScreen extends StatefulWidget {
  const GsmToolsHistoryScreen({super.key});

  @override
  State<GsmToolsHistoryScreen> createState() => _GsmToolsHistoryScreenState();
}

class _GsmToolsHistoryScreenState extends State<GsmToolsHistoryScreen> {
  bool loading = true;
  bool loadingMore = false;
  String? error;
  List<Map<String, dynamic>> orders = [];
  int page = 1;
  int lastPage = 1;

  List<Map<String, dynamic>> _asMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : {};
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
      final data = await context.read<AppStore>().loadGsmOrderHistory(page: 1);
      if (!mounted) return;
      final meta = _asMap(data['meta']);
      setState(() {
        orders = _asMaps(data['data']);
        page = (meta['current_page'] as num?)?.toInt() ?? 1;
        lastPage = (meta['last_page'] as num?)?.toInt() ?? 1;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not load order history.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || page >= lastPage) return;
    setState(() => loadingMore = true);
    try {
      final data = await context.read<AppStore>().loadGsmOrderHistory(page: page + 1);
      if (!mounted) return;
      final meta = _asMap(data['meta']);
      setState(() {
        orders = [...orders, ..._asMaps(data['data'])];
        page = (meta['current_page'] as num?)?.toInt() ?? page + 1;
        lastPage = (meta['last_page'] as num?)?.toInt() ?? lastPage;
        loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Order History', style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/gsm-tools'),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: error != null
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    )
                  : orders.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'No orders yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.pixels > n.metrics.maxScrollExtent - 240) {
                              _loadMore();
                            }
                            return false;
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                            itemCount: orders.length + (loadingMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i >= orders.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return _GsmOrderHistoryRow(
                                order: orders[i],
                                onTap: () => context.push('/gsm-tools/orders/${orders[i]['id']}'),
                              );
                            },
                          ),
                        ),
            ),
    );
  }
}

class _GsmOrderHistoryRow extends StatelessWidget {
  const _GsmOrderHistoryRow({required this.order, required this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final raw = '${order['status'] ?? ''}';
    final status = raw == 'pending' ? 'processing' : raw;
    final label = status == 'processing' ? 'PROCESSING' : '${order['status_label'] ?? status}'.toUpperCase();
    final color = status == 'processing'
        ? const Color(0xFF1D4ED8)
        : status == 'completed'
            ? const Color(0xFF047857)
            : status == 'failed' || status == 'cancelled'
                ? const Color(0xFFB91C1C)
                : AppColors.primary;
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
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GsmServiceLogo(url: '${order['image_url'] ?? ''}', size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${order['service_name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('${order['reference']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      if ('${order['eta_label'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${order['eta_label']}',
                          style: const TextStyle(color: Color(0xFF1D4ED8), fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(label, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: color)),
                ),
              ],
            ),
          ),
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
    final eta = '${service['eta_label'] ?? 'INSTANT'}'.trim();
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
                          if (eta.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                eta.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: Color(0xFF1D4ED8)),
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
  bool refreshing = false;
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
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    } else if (mounted) {
      setState(() => refreshing = true);
    }
    try {
      final data = await context.read<AppStore>().fetchGsmOrder(widget.id);
      if (!mounted) return;
      setState(() {
        order = Map<String, dynamic>.from(data['order'] as Map);
        loading = false;
        refreshing = false;
      });
      _syncPoll();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        refreshing = false;
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
    final rawStatus = '${order?['status'] ?? ''}';
    final status = rawStatus == 'pending' ? 'processing' : rawStatus;
    final statusLabel = status == 'processing' ? 'PROCESSING' : '${order?['status_label'] ?? status}'.toUpperCase();
    final resultNote = '${order?['admin_result_note'] ?? ''}';
    final email = '${order?['contact_email'] ?? ''}';
    final hasEmailField = fields.any((f) {
      final name = '${f['name']}'.toLowerCase();
      final label = '${f['label']}'.toLowerCase();
      return f['type'] == 'email' || name == 'email' || label == 'email';
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(order?['reference']?.toString() ?? 'GSM order', style: const TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/gsm-tools'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: refreshing ? null : () => _load(silent: true),
            icon: refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 14, offset: Offset(0, 6))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GsmServiceLogo(url: '${order?['image_url'] ?? ''}', size: 58),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${order?['service_name'] ?? 'GSM service'}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, height: 1.2),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.4, color: _statusColor(status)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PAID FROM WALLET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFC2410C), letterSpacing: 0.6)),
                              const SizedBox(height: 4),
                              Text('GH₵${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF9A3412))),
                              if (status == 'processing')
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text('Processing now. Watch System Reply below.', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF9A3412), fontSize: 13)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        const SizedBox(height: 12),
                        if (email.isNotEmpty && !hasEmailField)
                          _OrderDetailRow(label: 'Email', value: email),
                        ...fields.map((f) {
                          final value = '${f['value'] ?? ''}';
                          final image = f['type'] == 'image' && value.startsWith('http');
                          if (image) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${f['label']}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(value, height: 180, width: double.infinity, fit: BoxFit.cover),
                                  ),
                                ],
                              ),
                            );
                          }
                          return _OrderDetailRow(label: '${f['label']}', value: value.isEmpty ? '—' : value);
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SystemReplyCard(
                    replies: replies,
                    resultNote: resultNote,
                    refreshing: refreshing,
                    waiting: status == 'processing' || rawStatus == 'pending',
                    onRefresh: () => _load(silent: true),
                  ),
                  if ((order?['failure_reason'] ?? '').toString().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text('${order!['failure_reason']}', style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w700)),
                    ),
                  if (order?['can_cancel'] == true) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFFB91C1C),
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel & refund', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _OrderDetailRow extends StatelessWidget {
  const _OrderDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _SystemReplyCard extends StatelessWidget {
  const _SystemReplyCard({
    required this.replies,
    required this.resultNote,
    required this.refreshing,
    required this.waiting,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> replies;
  final String resultNote;
  final bool refreshing;
  final bool waiting;
  final VoidCallback onRefresh;

  String _when(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasReplies = replies.isNotEmpty;
    final hasNote = resultNote.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Reply',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      Text(
                        'Updates automatically',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (waiting)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0x1A34D399),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        if (refreshing)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.6, color: Color(0xFF34D399)),
                          )
                        else
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle),
                          ),
                        const SizedBox(width: 6),
                        Text(
                          refreshing ? 'Refreshing' : 'Live',
                          style: const TextStyle(
                            color: Color(0xFF6EE7B7),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: onRefresh,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: refreshing ? const Color(0xFF34D399) : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: !hasReplies && !hasNote
                ? Column(
                    children: [
                      SizedBox(
                        height: 36,
                        width: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: waiting ? AppColors.primary : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        waiting ? 'Waiting for a system reply…' : 'No system reply on this order.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        waiting
                            ? 'We check every few seconds. Pull down or tap refresh anytime.'
                            : 'There is nothing more from the system.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      if (hasNote && !hasReplies)
                        _SystemReplyBubble(
                          body: resultNote,
                          author: 'System',
                          when: '',
                        ),
                      for (final reply in replies)
                        _SystemReplyBubble(
                          body: '${reply['body'] ?? ''}',
                          author: '${reply['admin'] ?? 'System'}',
                          when: _when('${reply['created_at'] ?? ''}'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SystemReplyBubble extends StatelessWidget {
  const _SystemReplyBubble({required this.body, required this.author, required this.when});

  final String body;
  final String author;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: const TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w700, height: 1.4, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            when.isEmpty ? author : '$author · $when',
            style: const TextStyle(fontSize: 11, color: Color(0xFFC2410C), fontWeight: FontWeight.w800),
          ),
        ],
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
