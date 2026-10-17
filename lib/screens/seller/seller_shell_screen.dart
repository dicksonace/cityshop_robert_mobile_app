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
                      case 'security':
                        context.push('/profile/security?tab=authenticator');
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
                    PopupMenuItem(value: 'security', child: Text('Google Authenticator')),
                  ],
                ),
                IconButton(
                  tooltip: 'Log out',
                  onPressed: _logout,
                  icon: const Icon(Icons.power_settings_new_rounded),
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
          onOpenStoreWeb: _openStoreOnWeb,
        );
    }
  }
}

const _cardShadow = [
  BoxShadow(color: Color(0x0F0F172A), blurRadius: 18, offset: Offset(0, 6)),
];

BoxDecoration _cardDecoration({double radius = 18}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: _cardShadow,
    );

Color _statusColor(String status) {
  final s = status.toLowerCase();
  if (s.contains('cancel') || s.contains('fail') || s.contains('refund')) return AppColors.danger;
  if (s.contains('deliver') || s.contains('complete')) return AppColors.emerald;
  if (s.contains('ship') || s.contains('transit')) return const Color(0xFF0EA5E9);
  if (s.contains('pack')) return const Color(0xFF8B5CF6);
  if (s.contains('process') || s.contains('confirm')) return AppColors.blue;
  return const Color(0xFFF59E0B);
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
    required this.onOpenStoreWeb,
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
  final VoidCallback onOpenStoreWeb;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (error != null) ...[
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
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
                const SizedBox(height: 6),
                Text(
                  _greeting(),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                ),
                const SizedBox(height: 14),
                _WalletHero(
                  available: _asDouble(stats['available_balance']),
                  pending: _asDouble(stats['pending_balance']),
                  earnings: _asDouble(stats['total_earnings']),
                  onOpenWallet: onOpenWallet,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: _cardDecoration(),
                  child: Row(
                    children: [
                      _QuickAction(
                        icon: Icons.add_box_rounded,
                        label: 'Add product',
                        color: AppColors.primary,
                        onTap: () async {
                          final created = await context.push<bool>('/seller/products/new');
                          if (created == true) onRefresh();
                        },
                      ),
                      _QuickAction(
                        icon: Icons.qr_code_2_rounded,
                        label: 'Receive',
                        color: AppColors.emerald,
                        onTap: () => context.push('/qr/receive'),
                      ),
                      _QuickAction(
                        icon: Icons.qr_code_scanner_rounded,
                        label: 'Scan to pay',
                        color: AppColors.blue,
                        onTap: () => context.push('/qr/scan'),
                      ),
                      _QuickAction(
                        icon: Icons.storefront_rounded,
                        label: 'Web store',
                        color: const Color(0xFF8B5CF6),
                        onTap: onOpenStoreWeb,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        icon: Icons.receipt_long_rounded,
                        color: AppColors.blue,
                        label: 'Orders',
                        value: '${_asInt(stats['total_orders'])}',
                        onTap: () => onOpenOrders(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        icon: Icons.inventory_2_rounded,
                        color: const Color(0xFF8B5CF6),
                        label: 'Live products',
                        value: '${_asInt(stats['live_products'])}',
                        onTap: onOpenProducts,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        icon: Icons.trending_up_rounded,
                        color: AppColors.emerald,
                        label: 'Earnings',
                        value: _compactMoney(_asDouble(stats['total_earnings'])),
                        onTap: onOpenWallet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionHeader(
                  title: 'Order pipeline',
                  subtitle: 'Tap a stage to open those orders',
                  action: 'View all',
                  onAction: () => onOpenOrders(),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
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
                const SizedBox(height: 22),
                _HealthCard(score: healthScore, tip: healthTip),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _SectionHeader(
                    title: 'Recent orders',
                    action: 'See all',
                    onAction: () => onOpenOrders(),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: _cardDecoration(),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          for (var i = 0; i < recent.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 66, color: AppColors.border),
                            _RecentOrderRow(
                              item: recent[i],
                              onTap: () {
                                final id = _asInt(recent[i]['id']);
                                if (id > 0) onOpenOrder(id);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                const _SectionHeader(title: 'Account'),
                const SizedBox(height: 10),
                Container(
                  decoration: _cardDecoration(),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        _AccountRow(
                          icon: Icons.verified_user_rounded,
                          color: AppColors.emerald,
                          title: 'Google Authenticator',
                          subtitle: 'Email codes and authenticator QR',
                          onTap: () => context.push('/profile/security?tab=authenticator'),
                        ),
                        const Divider(height: 1, indent: 66, color: AppColors.border),
                        _AccountRow(
                          icon: Icons.privacy_tip_rounded,
                          color: AppColors.blue,
                          title: 'Account, privacy & delete',
                          subtitle: 'Privacy policy, support, and account deletion',
                          onTap: () => context.push('/profile/edit'),
                        ),
                      ],
                    ),
                  ),
                ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.action, this.onAction});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            child: Text(action!),
          ),
      ],
    );
  }
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x40EA580C), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)),
            ),
          ),
          Positioned(
            right: 50,
            bottom: -70,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Available balance',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money.format(available),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _HeroPill(
                        icon: Icons.hourglass_bottom_rounded,
                        label: 'Pending funds',
                        value: _money.format(pending),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroPill(
                        icon: Icons.insights_rounded,
                        label: 'Total earned',
                        value: _compactMoney(earnings),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: onOpenWallet,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                    label: const Text('Withdraw'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.white70),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDecoration(radius: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
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
    return Container(
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? color.withValues(alpha: 0.35) : Colors.transparent),
        boxShadow: active ? null : _cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? color : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: active ? Colors.white : color),
                ),
                const Spacer(),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: active ? color : AppColors.textMuted,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.score, required this.tip});

  final int score;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppColors.emerald
        : score >= 50
            ? const Color(0xFFF59E0B)
            : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: (score / 100).clamp(0, 1).toDouble(),
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.14),
                  ),
                ),
                Text('$score', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Store health', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  score >= 80
                      ? 'Strong store score'
                      : score >= 50
                          ? 'Good — a few upgrades left'
                          : 'Needs attention',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                if (tip != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    tip!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = (item['status'] as String? ?? '').replaceAll('_', ' ');
    final color = _statusColor(status);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.ringOrange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.shopping_bag_rounded, color: AppColors.primary, size: 20),
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
                    [item['order_number'], item['buyer_name']]
                        .whereType<String>()
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money.format(_asDouble(item['amount'])),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (status.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
