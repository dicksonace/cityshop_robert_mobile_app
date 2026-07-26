import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class WalletTab extends StatefulWidget {
  const WalletTab({super.key});

  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? funding;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      setState(() => loading = false);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await store.loadWallet();
      funding = await store.loadManualFunding();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _topUp() async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String network = 'mtn';
    XFile? proof;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Manual wallet top-up', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (GH₵)'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: network,
                    decoration: const InputDecoration(labelText: 'Network'),
                    items: const [
                      DropdownMenuItem(value: 'mtn', child: Text('MTN')),
                      DropdownMenuItem(value: 'telecel', child: Text('Telecel')),
                      DropdownMenuItem(value: 'airteltigo', child: Text('AirtelTigo')),
                    ],
                    onChanged: (v) => setModal(() => network = v ?? 'mtn'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(labelText: 'Payment reference (optional)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
                      if (file != null) setModal(() => proof = file);
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: Text(proof == null ? 'Upload payment proof' : 'Proof selected'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Submit'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;
    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount (min GH₵10)')),
      );
      return;
    }
    if (proof == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment proof is required')),
      );
      return;
    }

    try {
      await context.read<AppStore>().submitWalletTopUp(
            amount: amount,
            network: network,
            proofPath: proof!.path,
            paymentReference: refCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Top-up submitted for verification')),
      );
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.isLoggedIn) {
      return _Guest(onLogin: () => context.push('/login'));
    }
    if (loading) return const FullPageLoader(label: 'Loading wallet…');
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final wallet = store.wallet;
    final enabled = funding?['enabled'] == true;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available balance', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  _money.format(wallet?.availableBalance ?? 0),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pending: ${_money.format(wallet?.pendingBalance ?? 0)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (enabled) ...[
            PrimaryButton(label: 'Top up wallet', onPressed: _topUp),
            const SizedBox(height: 12),
            if (funding?['instructions'] != null)
              Text(
                '${funding!['instructions']}',
                style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
            const SizedBox(height: 8),
            if (funding?['accounts'] is List)
              for (final acc in (funding!['accounts'] as List).whereType<Map>())
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${acc['network'] ?? acc['name'] ?? 'Account'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${acc['number'] ?? acc['account_number'] ?? ''}'),
                ),
          ] else
            const Text(
              'Manual top-up is currently unavailable. Contact support.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      setState(() => loading = false);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await store.loadOrders();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.isLoggedIn) return _Guest(onLogin: () => context.push('/login'));
    if (loading) return const FullPageLoader(label: 'Loading orders…');
    if (error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ]));
    }
    if (store.orders.isEmpty) {
      return const Center(child: Text('No orders yet', style: TextStyle(fontWeight: FontWeight.w700)));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: store.orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final order = store.orders[index];
          return InkWell(
            onTap: () => context.push('/orders/${order.id}'),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        (order.status ?? '').toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(order.storeName ?? 'Seller', style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Text(_money.format(order.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('${order.items.length} item(s) · ${order.paymentStatus ?? ''}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool loading = true;
  String? error;
  dynamic order;

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
      order = await context.read<AppStore>().fetchOrder(widget.orderId);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      appBar: AppBar(title: Text(o?.orderNumber ?? 'Order')),
      body: loading
          ? const FullPageLoader(label: 'Loading order…')
          : error != null
              ? Center(child: Text(error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Status: ${o.status}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Payment: ${o.paymentStatus} · ${o.paymentMethod ?? o.paymentChannel ?? ''}'),
                    if (o.receiverName != null) Text('Ship to: ${o.receiverName}, ${o.city}, ${o.region}'),
                    const SizedBox(height: 12),
                    Text(_money.format(o.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accent)),
                    const Divider(height: 28),
                    for (final item in o.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('Qty ${item.quantity} · ${item.status ?? ''}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_money.format(item.lineTotal)),
                            if ((item.status ?? '').toLowerCase().contains('deliver') ||
                                (item.status ?? '').toLowerCase() == 'shipped' ||
                                (item.status ?? '').toLowerCase() == 'awaiting_confirmation')
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await context.read<AppStore>().confirmDelivery(o.id, item.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Delivery confirmed')),
                                      );
                                      _load();
                                    }
                                  } on ApiException catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                                    }
                                  }
                                },
                                child: const Text('Confirm'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _Guest extends StatelessWidget {
  const _Guest({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Login to continue', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onLogin, child: const Text('Login')),
        ],
      ),
    );
  }
}
