import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../screens/account/wallet_orders_screens.dart';
import '../../screens/chat/messages_screens.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tab_refresh.dart';
import 'seller_orders_screens.dart';
import 'seller_products_screens.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _asInt(dynamic value) => _asDouble(value).toInt();

class SellerShellScreen extends StatefulWidget {
  const SellerShellScreen({super.key});

  @override
  State<SellerShellScreen> createState() => _SellerShellScreenState();
}

class _SellerShellScreenState extends State<SellerShellScreen> with AutoRefreshTab {
  int _tab = 0;
  String _ordersStage = 'all';
  bool loading = true;
  String? error;
  Map<String, dynamic> dashboard = {};

  @override
  int? get tabIndex => 0;

  @override
  bool get tabAlreadyHasData => dashboard.isNotEmpty;

  @override
  Future<void> refreshTabData({required bool background}) => _load(background: background);

  Future<void> _load({bool background = false}) async {
    if (!mounted) return;
    if (!background) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final store = context.read<AppStore>();
      final data = await store.loadSellerDashboard();
      // Keep the bell badge current while Home is on screen.
      try {
        await store.loadNotifications();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        dashboard = data;
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (!background || dashboard.isEmpty) error = e.message;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!background || dashboard.isEmpty) error = e.toString();
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

  String? _storeWebUrl() {
    final profile = dashboard['profile'] is Map
        ? Map<String, dynamic>.from(dashboard['profile'] as Map)
        : const <String, dynamic>{};
    final slug = '${profile['slug'] ?? ''}'.trim();
    if (slug.isNotEmpty) return ApiConfig.storeWebUrl(slug);
    final fallback = '${dashboard['store_url'] ?? ''}'.trim();
    return fallback.isEmpty ? null : fallback;
  }

  Future<void> _openStoreOnWeb({bool copy = false}) async {
    final url = _storeWebUrl();
    if (url == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your public store link is not ready yet.')),
      );
      return;
    }
    if (copy) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store link copied.')),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the store in the browser.')),
      );
    }
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
      appBar: _tab == 0
          ? AppBar(
              title: Text(storeName.isEmpty ? 'Seller Hub' : storeName),
              actions: [
                IconButton(
                  tooltip: 'Scan QR to pay',
                  onPressed: () => context.push('/qr/scan'),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
                IconButton(
                  tooltip: 'Receive payment',
                  onPressed: () => context.push('/qr/receive'),
                  icon: const Icon(Icons.qr_code_2_rounded),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => context.push('/notifications'),
                  icon: Badge(
                    isLabelVisible: store.unreadNotifications > 0,
                    label: Text(
                      '${store.unreadNotifications > 9 ? '9+' : store.unreadNotifications}',
                    ),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                ),
                IconButton(
                  tooltip: 'Wallet',
                  onPressed: () => setState(() => _tab = 3),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More tools',
                  onSelected: (value) {
                    switch (value) {
                      case 'store_web':
                        _openStoreOnWeb();
                      case 'store':
                        context.push('/seller/store');
                      case 'reviews':
                        context.push('/seller/reviews');
                      case 'promos':
                        context.push('/seller/promotions');
                      case 'payments':
                        context.push('/seller/payment-methods');
                      case 'followers':
                        context.push('/seller/followers');
                      case 'refunds':
                        context.push('/seller/refunds');
                      case 'activation':
                        context.push('/seller/activation');
                      case 'order_sms':
                        context.push('/seller/order-sms');
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'store_web', child: Text('Web store')),
                    PopupMenuItem(value: 'store', child: Text('Store look')),
                    PopupMenuItem(value: 'reviews', child: Text('Reviews')),
                    PopupMenuItem(value: 'promos', child: Text('Promos')),
                    PopupMenuItem(value: 'payments', child: Text('Payment methods')),
                    PopupMenuItem(value: 'followers', child: Text('Followers')),
                    PopupMenuItem(value: 'refunds', child: Text('Refunds')),
                    PopupMenuItem(value: 'activation', child: Text('Seller fee')),
                    PopupMenuItem(value: 'order_sms', child: Text('Order SMS')),
                  ],
                ),
                IconButton(
                  tooltip: 'Log out',
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                ),
              ],
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: ActiveTab(
          index: _tab,
          child: _tabBody(storeName),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: AppColors.accent,
          indicatorShape: const CircleBorder(),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final active = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.accent : AppColors.textSecondary,
            );
          }),
        ),
        child: ColoredBox(
          color: Colors.white,
          child: SafeArea(
            top: false,
            maintainBottomViewPadding: true,
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              height: 68,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined, color: _tab == 0 ? Colors.white : AppColors.textSecondary),
                  selectedIcon: Icon(Icons.home_rounded, color: _tab == 0 ? Colors.white : AppColors.textSecondary),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined, color: _tab == 1 ? Colors.white : AppColors.textSecondary),
                  selectedIcon: Icon(Icons.receipt_long, color: _tab == 1 ? Colors.white : AppColors.textSecondary),
                  label: 'Orders',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined, color: _tab == 2 ? Colors.white : AppColors.textSecondary),
                  selectedIcon: Icon(Icons.inventory_2, color: _tab == 2 ? Colors.white : AppColors.textSecondary),
                  label: 'Products',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined, color: _tab == 3 ? Colors.white : AppColors.textSecondary),
                  selectedIcon: Icon(Icons.account_balance_wallet, color: _tab == 3 ? Colors.white : AppColors.textSecondary),
                  label: 'Wallet',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline, color: _tab == 4 ? Colors.white : AppColors.textSecondary),
                  selectedIcon: Icon(Icons.chat_bubble, color: _tab == 4 ? Colors.white : AppColors.textSecondary),
                  label: 'Messages',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBody(String storeName) {
    switch (_tab) {
      case 1:
        return SellerOrdersTab(initialStage: _ordersStage);
      case 2:
        return const SellerProductsTab();
      case 3:
        return const SafeArea(bottom: false, child: WalletTab(shellTabIndex: 3));
      case 4:
        return const SafeArea(bottom: false, child: MessagesTab(shellTabIndex: 4));
      default:
        return _OverviewTab(
          loading: loading,
          error: error,
          dashboard: dashboard,
          storeName: storeName,
          onRefresh: _load,
          onOpenOrders: _openOrders,
          onOpenOrder: (id) => context.push('/seller/orders/$id'),
          onOpenProducts: () => setState(() => _tab = 2),
          onOpenWallet: () => setState(() => _tab = 3),
        );
    }
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.loading,
    required this.error,
    required this.dashboard,
    required this.storeName,
    required this.onRefresh,
    required this.onOpenOrders,
    required this.onOpenOrder,
    required this.onOpenProducts,
    required this.onOpenWallet,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic> dashboard;
  final String storeName;
  final Future<void> Function() onRefresh;
  final void Function({String stage}) onOpenOrders;
  final void Function(int id) onOpenOrder;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenWallet;

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
    final recent = (dashboard['recent_orders'] is List ? dashboard['recent_orders'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final tips = (health['tips'] is List ? health['tips'] as List : const [])
        .take(3)
        .map((tip) => '$tip')
        .toList();
    final healthScore = _asInt(health['score']);
    final stages = [
      ('Pending', 'new', pipeline['pending'], Icons.schedule_rounded, const Color(0xFFF59E0B)),
      ('Processing', 'processing', pipeline['processing'], Icons.sync_rounded, const Color(0xFF3B82F6)),
      ('Packed', 'packing', pipeline['packed'], Icons.inventory_2_rounded, const Color(0xFF8B5CF6)),
      ('Shipped', 'delivery', pipeline['shipped'], Icons.local_shipping_rounded, const Color(0xFF0EA5E9)),
      ('Awaiting', 'awaiting', pipeline['awaiting_confirmation'], Icons.move_to_inbox_rounded, const Color(0xFF14B8A6)),
      ('Delivered', 'completed', pipeline['delivered'], Icons.verified_rounded, const Color(0xFF059669)),
    ];
    final healthTip = tips.isNotEmpty ? tips.first : null;

    return Column(
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2, color: AppColors.accent),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(onPressed: onRefresh, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  ),
                ],
                if (profile['needs_activation'] == true) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFEDD5),
                        child: Icon(Icons.lock_open, color: AppColors.primary),
                      ),
                      title: Text(
                        'Pay GH₵${_asDouble(profile['activation_fee']).toStringAsFixed(2)} seller fee',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text('Your store stays hidden until this is paid.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/seller/activation'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _WalletHero(
                  available: _asDouble(stats['available_balance']),
                  pending: _asDouble(stats['pending_balance']),
                  earnings: _asDouble(stats['total_earnings']),
                  onOpenWallet: onOpenWallet,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        icon: Icons.receipt_long_outlined,
                        label: 'Orders',
                        value: '${_asInt(stats['total_orders'])}',
                        onTap: () => onOpenOrders(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        icon: Icons.inventory_2_outlined,
                        label: 'Live products',
                        value: '${_asInt(stats['live_products'])}',
                        onTap: onOpenProducts,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        icon: Icons.trending_up_rounded,
                        label: 'Earnings',
                        value: _money.format(_asDouble(stats['total_earnings'])),
                        onTap: onOpenWallet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('Order pipeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                  'Tap a stage to open those orders',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.08,
                  children: [
                    for (final stage in stages)
                      _PipelineTile(
                        label: stage.$1,
                        count: _asInt(stage.$3),
                        icon: stage.$4,
                        color: stage.$5,
                        onTap: () => onOpenOrders(stage: stage.$2),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
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
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Store health', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(
                                  healthScore >= 80
                                      ? 'Strong store score'
                                      : healthScore >= 50
                                          ? 'Good — a few upgrades left'
                                          : 'Needs attention',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '$healthScore',
                              style: const TextStyle(
                                color: Color(0xFF15803D),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (healthScore / 100).clamp(0, 1),
                          minHeight: 7,
                          color: const Color(0xFF22C55E),
                          backgroundColor: const Color(0xFFE5E7EB),
                        ),
                      ),
                      if (healthTip != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '* $healthTip',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                if (recent.isNotEmpty) ...[
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
                  const SizedBox(height: 8),
                  ...recent.map((item) {
                    final status = (item['status'] as String? ?? '').replaceAll('_', ' ');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            final id = _asInt(item['id']);
                            if (id > 0) onOpenOrder(id);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Color(0xFFFFF7ED),
                                  child: Icon(Icons.shopping_bag_outlined, color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['product_name'] as String? ?? 'Order',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          item['order_number'],
                                          item['buyer_name'],
                                          if (status.isNotEmpty) status,
                                        ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _money.format(_asDouble(item['amount'])),
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _compactMoney(double value) {
  if (value >= 1000000) return 'GH₵${(value / 1000000).toStringAsFixed(1)}m';
  if (value >= 10000) return 'GH₵${(value / 1000).toStringAsFixed(value >= 100000 ? 0 : 1)}k';
  return _money.format(value);
}

class _WalletHero extends StatelessWidget {
  const _WalletHero({
    required this.available,
    required this.pending,
    required this.earnings,
    required this.onOpenWallet,
  });

  final double available;
  final double pending;
  final double earnings;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenWallet,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFFEA580C), Color(0xFFF97316), Color(0xFFFB923C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money.format(available),
                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1.05),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _HeroPill(
                        label: 'Pending funds',
                        value: _money.format(pending),
                        hint: 'Waiting for release',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroPill(
                        label: 'Total earned',
                        value: _compactMoney(earnings),
                        hint: 'All-time sales',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          ),
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppColors.accent),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineTile extends StatelessWidget {
  const _PipelineTile({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: active ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
