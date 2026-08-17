import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../screens/account/wallet_orders_screens.dart';
import '../../screens/chat/messages_screens.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/tab_refresh.dart';
import 'seller_orders_screens.dart';
import 'seller_products_screens.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class SellerShellScreen extends StatefulWidget {
  const SellerShellScreen({super.key});

  @override
  State<SellerShellScreen> createState() => _SellerShellScreenState();
}

class _SellerShellScreenState extends State<SellerShellScreen> {
  int _tab = 0;
  String _ordersStage = 'all';
  bool loading = true;
  String? error;
  Map<String, dynamic> dashboard = {};

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
      final data = await context.read<AppStore>().loadSellerDashboard();
      if (!mounted) return;
      setState(() {
        dashboard = data;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
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

  void _openOrders({String stage = 'all'}) {
    setState(() {
      _tab = 1;
      _ordersStage = stage;
    });
  }

  Future<void> _logout() async {
    await context.read<AppStore>().logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final user = store.user;
    final profile = dashboard['profile'] is Map
        ? Map<String, dynamic>.from(dashboard['profile'] as Map)
        : null;
    final storeName = profile?['store_name'] as String? ??
        user?.sellerStoreName ??
        user?.name ??
        'Seller';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ActiveTab(
        index: _tab,
        child: IndexedStack(
          index: _tab,
          children: [
            _OverviewTab(
              loading: loading,
              error: error,
              dashboard: dashboard,
              storeName: storeName,
              onRefresh: _load,
              onLogout: _logout,
              onOpenOrders: _openOrders,
              onOpenOrder: (id) => context.push('/seller/orders/$id'),
              onOpenProducts: () => setState(() => _tab = 2),
              onOpenWallet: () => setState(() => _tab = 3),
              onOpenPayments: () => context.push('/seller/payment-methods'),
              onOpenStore: () async {
                final url = dashboard['store_url'] as String?;
                if (url == null || url.isEmpty) return;
                final uri = Uri.tryParse(url);
                if (uri == null) return;
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            SellerOrdersTab(initialStage: _ordersStage),
            const SellerProductsTab(),
            const SafeArea(bottom: false, child: WalletTab(shellTabIndex: 3)),
            const SafeArea(bottom: false, child: MessagesTab(shellTabIndex: 4)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Products'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Messages'),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.loading,
    required this.error,
    required this.dashboard,
    required this.storeName,
    required this.onRefresh,
    required this.onLogout,
    required this.onOpenStore,
    required this.onOpenOrders,
    required this.onOpenOrder,
    required this.onOpenProducts,
    required this.onOpenWallet,
    required this.onOpenPayments,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic> dashboard;
  final String storeName;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;
  final Future<void> Function() onOpenStore;
  final void Function({String stage}) onOpenOrders;
  final void Function(int id) onOpenOrder;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenPayments;

  @override
  Widget build(BuildContext context) {
    final profile = dashboard['profile'] is Map
        ? Map<String, dynamic>.from(dashboard['profile'] as Map)
        : <String, dynamic>{};
    final stats = dashboard['stats'] is Map
        ? Map<String, dynamic>.from(dashboard['stats'] as Map)
        : <String, dynamic>{};
    final pipeline = dashboard['order_pipeline_counts'] is Map
        ? Map<String, dynamic>.from(dashboard['order_pipeline_counts'] as Map)
        : <String, dynamic>{};
    final health = dashboard['store_health'] is Map
        ? Map<String, dynamic>.from(dashboard['store_health'] as Map)
        : <String, dynamic>{};
    final recent = (dashboard['recent_orders'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Seller Hub'),
            actions: [
              IconButton(
                tooltip: 'View store',
                onPressed: onOpenStore,
                icon: const Icon(Icons.storefront_outlined),
              ),
              IconButton(
                tooltip: 'Log out',
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          if (loading)
            const SliverFillRemaining(child: FullPageLoader(label: 'Loading dashboard…'))
          else if (error != null)
            SliverFillRemaining(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: onRefresh, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    storeName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Overview of sales, stock, and payouts',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (profile['needs_activation'] == true) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        title: Text(
                          'Pay GH₵${((profile['activation_fee'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} seller fee',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text('Your store stays hidden from buyers until this is paid.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/seller/activation'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                    children: [
                      _StatCard(
                        label: 'Available',
                        value: _money.format((stats['available_balance'] as num?)?.toDouble() ?? 0),
                        onTap: onOpenWallet,
                      ),
                      _StatCard(
                        label: 'Earnings',
                        value: _money.format((stats['total_earnings'] as num?)?.toDouble() ?? 0),
                        onTap: onOpenWallet,
                      ),
                      _StatCard(
                        label: 'Orders',
                        value: '${(stats['total_orders'] as num?)?.toInt() ?? 0}',
                        onTap: () => onOpenOrders(),
                      ),
                      _StatCard(
                        label: 'Live products',
                        value: '${(stats['live_products'] as num?)?.toInt() ?? 0}',
                        onTap: onOpenProducts,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('Order pipeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in [
                        ('Pending', 'new', pipeline['pending']),
                        ('Processing', 'processing', pipeline['processing']),
                        ('Packed', 'packing', pipeline['packed']),
                        ('Shipped', 'delivery', pipeline['shipped']),
                        ('Awaiting', 'awaiting', pipeline['awaiting_confirmation']),
                        ('Delivered', 'completed', pipeline['delivered']),
                      ])
                        ActionChip(
                          label: Text('${entry.$1}: ${(entry.$3 as num?)?.toInt() ?? 0}'),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.border),
                          onPressed: () => onOpenOrders(stage: entry.$2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Store health · ${((health['score'] as num?)?.toInt() ?? 0)}/100',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (((health['score'] as num?)?.toDouble() ?? 0) / 100).clamp(0, 1),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFF0F766E),
                          backgroundColor: const Color(0xFFE5E7EB),
                        ),
                        if ((health['tips'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          ...(health['tips'] as List).take(3).map(
                                (tip) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text('• $tip', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                ),
                              ),
                        ],
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: onOpenPayments,
                          child: const Text('Payment methods'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('More tools', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(label: const Text('Store look'), onPressed: () => context.push('/seller/store')),
                      ActionChip(label: const Text('Reviews'), onPressed: () => context.push('/seller/reviews')),
                      ActionChip(label: const Text('Promotions'), onPressed: () => context.push('/seller/promotions')),
                      ActionChip(label: const Text('Followers'), onPressed: () => context.push('/seller/followers')),
                      ActionChip(label: const Text('Refunds'), onPressed: () => context.push('/seller/refunds')),
                      ActionChip(label: const Text('Payment methods'), onPressed: onOpenPayments),
                      ActionChip(label: const Text('Seller fee'), onPressed: () => context.push('/seller/activation')),
                      ActionChip(label: const Text('Order SMS'), onPressed: () => context.push('/seller/order-sms')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Recent orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      TextButton(
                        onPressed: () => onOpenOrders(),
                        child: const Text('See all'),
                      ),
                    ],
                  ),
                  if (recent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No recent orders yet.', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ...recent.map((item) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFECFDF5),
                        child: Icon(Icons.receipt_long, color: Color(0xFF047857), size: 20),
                      ),
                      title: Text(
                        item['product_name'] as String? ?? 'Order',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          item['order_number'],
                          item['buyer_name'],
                          item['status'],
                        ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                      ),
                      trailing: Text(
                        _money.format((item['amount'] as num?)?.toDouble() ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () {
                        final id = (item['id'] as num?)?.toInt() ?? 0;
                        if (id > 0) onOpenOrder(id);
                      },
                    );
                  }),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}
