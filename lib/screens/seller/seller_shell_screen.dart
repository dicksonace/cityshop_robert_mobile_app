import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class SellerShellScreen extends StatefulWidget {
  const SellerShellScreen({super.key});

  @override
  State<SellerShellScreen> createState() => _SellerShellScreenState();
}

class _SellerShellScreenState extends State<SellerShellScreen> {
  int _tab = 0;
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

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon in the app. Use the web Seller Hub for now.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      body: IndexedStack(
        index: _tab,
        children: [
          _OverviewTab(
            loading: loading,
            error: error,
            dashboard: dashboard,
            storeName: storeName,
            onRefresh: _load,
            onComingSoon: _comingSoon,
            onLogout: _logout,
            onOpenStore: () async {
              final url = dashboard['store_url'] as String?;
              if (url == null || url.isEmpty) {
                _comingSoon('Store page');
                return;
              }
              final uri = Uri.tryParse(url);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
          _PlaceholderTab(
            title: 'Orders',
            subtitle: 'Manage your sales pipeline on web for now.',
            onRefresh: _load,
            onComingSoon: () => _comingSoon('Orders'),
          ),
          _PlaceholderTab(
            title: 'Products',
            subtitle: 'Product tools are coming to the app next.',
            onRefresh: _load,
            onComingSoon: () => _comingSoon('Products'),
          ),
          _PlaceholderTab(
            title: 'Wallet',
            subtitle: 'Wallet & withdrawals stay on web Seller Hub for now.',
            onRefresh: _load,
            onComingSoon: () => _comingSoon('Wallet'),
          ),
          _PlaceholderTab(
            title: 'Messages',
            subtitle: 'Open Messages from Account soon — use web inbox for now.',
            onRefresh: _load,
            onComingSoon: () => _comingSoon('Messages'),
          ),
        ],
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
    required this.onComingSoon,
    required this.onLogout,
    required this.onOpenStore,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic> dashboard;
  final String storeName;
  final Future<void> Function() onRefresh;
  final void Function(String feature) onComingSoon;
  final Future<void> Function() onLogout;
  final Future<void> Function() onOpenStore;

  @override
  Widget build(BuildContext context) {
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
                    'Overview · more tools coming soon',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
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
                      ),
                      _StatCard(
                        label: 'Earnings',
                        value: _money.format((stats['total_earnings'] as num?)?.toDouble() ?? 0),
                      ),
                      _StatCard(
                        label: 'Orders',
                        value: '${(stats['total_orders'] as num?)?.toInt() ?? 0}',
                      ),
                      _StatCard(
                        label: 'Live products',
                        value: '${(stats['live_products'] as num?)?.toInt() ?? 0}',
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
                        ('Pending', pipeline['pending']),
                        ('Processing', pipeline['processing']),
                        ('Packed', pipeline['packed']),
                        ('Shipped', pipeline['shipped']),
                        ('Awaiting', pipeline['awaiting_confirmation']),
                        ('Delivered', pipeline['delivered']),
                      ])
                        Chip(
                          label: Text('${entry.$1}: ${(entry.$2 as num?)?.toInt() ?? 0}'),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.border),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Recent orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      TextButton(
                        onPressed: () => onComingSoon('Orders'),
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
                      onTap: () => onComingSoon('Order details'),
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
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
    required this.onComingSoon,
  });

  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;
  final VoidCallback onComingSoon;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
        children: [
          Icon(Icons.construction_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          FilledButton(onPressed: onComingSoon, child: const Text('Coming soon')),
        ],
      ),
    );
  }
}
