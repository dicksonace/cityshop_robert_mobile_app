import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
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

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _topUp() async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String network = 'mtn';
    XFile? proof;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Top up wallet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                  const SizedBox(height: 6),
                  const Text(
                    'Pay via MoMo, then upload proof. We’ll credit your wallet after verification.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount (GH₵)',
                      prefixText: 'GH₵ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: network,
                    decoration: const InputDecoration(labelText: 'Network used'),
                    items: const [
                      DropdownMenuItem(value: 'mtn', child: Text('MTN')),
                      DropdownMenuItem(value: 'telecel', child: Text('Telecel')),
                      DropdownMenuItem(value: 'airteltigo', child: Text('AirtelTigo')),
                    ],
                    onChanged: (v) => setModal(() => network = v ?? 'mtn'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Payment reference',
                      hintText: 'Transaction ID / MoMo reference',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final file = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 85,
                      );
                      if (file != null) setModal(() => proof = file);
                    },
                    icon: Icon(proof == null ? Icons.image_outlined : Icons.check_circle, color: AppColors.accent),
                    label: Text(proof == null ? 'Upload payment proof *' : 'Proof selected'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Submit for verification'),
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

  Color _networkColor(String network) {
    switch (network.toLowerCase()) {
      case 'mtn':
        return const Color(0xFFFFCC00);
      case 'telecel':
        return const Color(0xFFE60000);
      case 'airteltigo':
        return const Color(0xFFED1C24);
      default:
        return AppColors.accent;
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
    final accounts = (funding?['accounts'] is List)
        ? (funding!['accounts'] as List).whereType<Map>().toList()
        : <Map>[];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available balance', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  _money.format(wallet?.availableBalance ?? 0),
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Pending: ${_money.format(wallet?.pendingBalance ?? 0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (enabled) ...[
            PrimaryButton(label: 'Top up wallet', onPressed: _topUp),
            const SizedBox(height: 18),
            const Text('Pay into these accounts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              funding?['instructions']?.toString() ??
                  'Send payment to one of the accounts below, then submit your proof and reference so we can credit your wallet.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final acc in accounts)
              _FundingAccountCard(
                network: '${acc['network'] ?? acc['name'] ?? 'Account'}',
                number: '${acc['number'] ?? acc['account_number'] ?? ''}',
                color: _networkColor('${acc['network'] ?? ''}'),
                onCopy: () {
                  final number = '${acc['number'] ?? acc['account_number'] ?? ''}';
                  if (number.isNotEmpty) _copy('Number', number);
                },
              ),
          ] else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Manual top-up is currently unavailable. Contact support.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _FundingAccountCard extends StatelessWidget {
  const _FundingAccountCard({
    required this.network,
    required this.number,
    required this.color,
    required this.onCopy,
  });

  final String network;
  final String number;
  final Color color;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              network.isNotEmpty ? network[0].toUpperCase() : 'M',
              style: TextStyle(fontWeight: FontWeight.w900, color: color == const Color(0xFFFFCC00) ? Colors.black87 : color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(network.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(number, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy number',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, color: AppColors.accent),
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

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'delivered':
      case 'completed':
        return AppColors.emerald;
      case 'cancelled':
      case 'failed':
        return AppColors.danger;
      case 'shipped':
      case 'processing':
        return AppColors.blue;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.isLoggedIn) return _Guest(onLogin: () => context.push('/login'));
    if (loading) return const FullPageLoader(label: 'Loading orders…');
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
    if (store.orders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.accent),
              SizedBox(height: 12),
              Text('No orders yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              SizedBox(height: 6),
              Text(
                'When you checkout, your orders will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: store.orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final order = store.orders[index];
          final color = _statusColor(order.status);
          return InkWell(
            onTap: () => context.push('/orders/${order.id}'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          (order.status ?? 'pending').toUpperCase(),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(order.storeName ?? 'Seller', style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(_money.format(order.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.accent)),
                      const Spacer(),
                      Text(
                        '${order.items.length} item(s) · ${(order.paymentStatus ?? '').toUpperCase()}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
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
  OrderModel? order;

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

  bool _canConfirm(OrderItemModel item) {
    final s = (item.status ?? '').toLowerCase();
    return s.contains('deliver') || s == 'shipped' || s == 'awaiting_confirmation';
  }

  String _statusHint(OrderItemModel item) {
    final s = (item.status ?? 'pending').toLowerCase();
    if (_canConfirm(item)) return 'Tap Confirm when you’ve received this item.';
    if (s == 'pending' || s == 'processing') return 'Waiting for seller to prepare / ship.';
    if (s == 'cancelled') return 'This item was cancelled.';
    return 'Status: ${item.status}';
  }

  Color _chipColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'delivered':
      case 'completed':
        return AppColors.emerald;
      case 'cancelled':
        return AppColors.danger;
      case 'shipped':
      case 'awaiting_confirmation':
        return AppColors.blue;
      default:
        return AppColors.accent;
    }
  }

  Future<void> _messageSeller() async {
    final o = order;
    if (o?.sellerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller chat is unavailable for this order')),
      );
      return;
    }
    try {
      final opened = await context.read<AppStore>().openConversation(sellerId: o!.sellerId!);
      if (!mounted) return;
      context.push('/messages/${opened.conversation.id}');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(o?.orderNumber ?? 'Order'),
        actions: [
          if (o?.sellerId != null)
            TextButton(
              onPressed: _messageSeller,
              child: const Text('Chat seller'),
            ),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading order…')
          : error != null
              ? Center(child: Text(error!))
              : o == null
                  ? const Center(child: Text('Order not found'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        _InfoCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      o.orderNumber,
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                    ),
                                  ),
                                  _StatusChip(label: o.status ?? 'pending', color: _chipColor(o.status)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _kv('Payment', '${(o.paymentStatus ?? '—').toUpperCase()} · ${(o.paymentMethod ?? o.paymentChannel ?? '—')}'),
                              if (o.storeName != null) _kv('Seller', o.storeName!),
                              if (o.createdAt != null) _kv('Placed', o.createdAt!),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Shipping', style: TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              Text(
                                [
                                  if (o.receiverName != null) o.receiverName!,
                                  if (o.city != null) o.city!,
                                  if (o.region != null) o.region!,
                                ].whereType<String>().join(', '),
                                style: const TextStyle(height: 1.35),
                              ),
                              if (o.receiverPhone != null) ...[
                                const SizedBox(height: 6),
                                Text(o.receiverPhone!, style: const TextStyle(color: AppColors.textSecondary)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoCard(
                          child: Column(
                            children: [
                              _moneyRow('Subtotal', o.subtotal),
                              _moneyRow('Shipping', o.shippingCost),
                              const Divider(height: 20),
                              Row(
                                children: [
                                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                  const Spacer(),
                                  Text(
                                    _money.format(o.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text('Items', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 10),
                        for (final item in o.items)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.productName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                      ),
                                    ),
                                    Text(
                                      _money.format(item.displayTotal),
                                      style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.accent),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Qty ${item.quantity} · ${_money.format(item.unitPrice)} each',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _StatusChip(label: item.status ?? 'pending', color: _chipColor(item.status)),
                                    const Spacer(),
                                    if (_canConfirm(item))
                                      ElevatedButton(
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
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text(e.message)),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text('Confirm delivery'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _statusHint(item),
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 78, child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(_money.format(value), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
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
          const Icon(Icons.lock_outline, size: 40, color: AppColors.accent),
          const SizedBox(height: 12),
          const Text('Login to continue', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onLogin, child: const Text('Login')),
        ],
      ),
    );
  }
}
