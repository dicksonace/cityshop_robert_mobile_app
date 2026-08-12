import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../services/push_notifications.dart';
import '../../services/recent_views.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/tab_refresh.dart';
import '../account/wallet_orders_screens.dart';
import '../chat/messages_screens.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class ShopShell extends StatefulWidget {
  const ShopShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends State<ShopShell> {
  final _search = TextEditingController();
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = context.read<AppStore>();
      if (store.isLoggedIn) {
        store.refreshNotificationCounts();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ShopShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = widget.initialTab;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Bag logo: home for buyers; seller/admin centre; login for guests.
  Future<void> _openBrandHome() async {
    final user = context.read<AppStore>().user;
    if (user == null) {
      context.push('/login');
      return;
    }
    final role = (user.role ?? '').toLowerCase();
    if (role == 'seller' || role == 'admin') {
      final base = ApiConfig.webBaseUrl.endsWith('/')
          ? ApiConfig.webBaseUrl.substring(0, ApiConfig.webBaseUrl.length - 1)
          : ApiConfig.webBaseUrl;
      final path = role == 'admin' ? '/admin/dashboard' : '/seller/dashboard';
      final uri = Uri.parse('$base$path');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $path')),
        );
      }
      return;
    }
    setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      body: SafeArea(
        // Keep the bottom inset for the tab bar. If SafeArea eats it here,
        // Android's system buttons sit on top of Shop / Wallet / Chat.
        bottom: false,
        child: ActiveTab(
          index: _tab,
          child: IndexedStack(
            index: _tab,
            children: [
              _ShopHome(
                searchController: _search,
                onOpenBrandHome: _openBrandHome,
              ),
              const WalletTab(),
              OrdersTab(
                onOpenWallet: () => setState(() => _tab = 1),
                onOpenMessages: () => setState(() => _tab = 3),
              ),
              const MessagesTab(),
              AccountSettingsTab(user: store.user),
            ],
          ),
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
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            if (store.isLoggedIn && (i == 0 || i == 2 || i == 3 || i == 4)) {
              store.refreshNotificationCounts();
            }
          },
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined, color: _tab == 0 ? Colors.white : AppColors.textSecondary),
              label: 'Shop',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined, color: _tab == 1 ? Colors.white : AppColors.textSecondary),
              label: 'Wallet',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: store.isLoggedIn && store.activeOrders > 0,
                label: Text('${store.activeOrders > 9 ? '9+' : store.activeOrders}'),
                child: Icon(Icons.inventory_2_outlined, color: _tab == 2 ? Colors.white : AppColors.textSecondary),
              ),
              label: 'My Order',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: store.unreadMessages > 0,
                label: Text('${store.unreadMessages > 9 ? '9+' : store.unreadMessages}'),
                child: Icon(Icons.chat_bubble_outline, color: _tab == 3 ? Colors.white : AppColors.textSecondary),
              ),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: store.unreadNotifications > 0,
                label: Text('${store.unreadNotifications > 9 ? '9+' : store.unreadNotifications}'),
                child: Icon(Icons.person_outline, color: _tab == 4 ? Colors.white : AppColors.textSecondary),
              ),
              label: 'Profile',
            ),
          ],
          ),
          ),
        ),
      ),
    );
  }
}

class _ShopHome extends StatefulWidget {
  const _ShopHome({
    required this.searchController,
    required this.onOpenBrandHome,
  });

  final TextEditingController searchController;
  final Future<void> Function() onOpenBrandHome;

  @override
  State<_ShopHome> createState() => _ShopHomeState();
}

class _ShopHomeState extends State<_ShopHome> with AutoRefreshTab {
  int _matchesTick = 0;
  Timer? _searchDebounce;

  @override
  int? get tabIndex => 0;

  @override
  bool get refreshNeedsLogin => false;

  @override
  bool get tabAlreadyHasData => context.read<AppStore>().products.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    widget.searchController.removeListener(_onSearchTextChanged);
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (!mounted) return;
    setState(() {});
    final q = widget.searchController.text.trim();
    _searchDebounce?.cancel();
    final store = context.read<AppStore>();
    if (q.isEmpty) {
      if (store.searchQuery.isNotEmpty || store.imageSearchActive) {
        store.loadShop(search: '');
      }
      return;
    }
    if (q == store.searchQuery.trim()) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<AppStore>().loadShop(search: widget.searchController.text);
    });
  }

  @override
  Future<void> refreshTabData({required bool background}) async {
    final store = context.read<AppStore>();
    await store.loadShop(search: widget.searchController.text);
    if (!mounted || background) return;
    // Recreating the picks-for-you strip is jarring mid-browse, so only do it
    // when the shopper asked for a refresh.
    setState(() => _matchesTick++);
  }

  Future<void> _pickImageSearch(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
              const Text('Search by photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 6),
              const Text(
                'Take a photo or upload one to find similar products on CityShop.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.ringOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
                ),
                title: const Text('Take photo', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Use your camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.ringOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
                ),
                title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Upload an existing picture'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !context.mounted) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);
    if (file == null || !context.mounted) return;

    final store = context.read<AppStore>();
    await store.searchByImage(file.path);
    if (!context.mounted) return;
    if (store.shopError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.shopError!)));
    } else if (store.products.isEmpty) {
      final hint = store.imageSearchKeywords.isNotEmpty
          ? 'No catalog match for “${store.imageSearchKeywords.take(3).join(', ')}”. Try a clearer close-up.'
          : 'No similar products found. Use a clear close-up of the product.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hint)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Column(
      children: [
        _TopBar(user: store.user, onOpenBrandHome: widget.onOpenBrandHome),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: refreshNow,
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _HeroBanner()),
                SliverToBoxAdapter(child: _CategoryShortcuts(store: store)),
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _Stat(value: '${store.totalProducts}', label: 'products'),
                        _Stat(
                          value: '${store.products.where((p) => p.freeShipping).length}',
                          label: 'free delivery',
                          color: AppColors.emerald,
                        ),
                        _Stat(
                          value: '${store.products.where((p) => p.inGhana).length}',
                          label: 'in Ghana',
                          color: AppColors.blue,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _LiveNowStrip(key: ValueKey('live-$_matchesTick'))),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.ringOrange),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SEARCH PRODUCTS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFFFEDD5), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 12),
                                const Icon(Icons.search, color: AppColors.textMuted),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: widget.searchController,
                                    decoration: const InputDecoration(
                                      hintText: 'Search products, stores, brands…',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: (q) {
                                      _searchDebounce?.cancel();
                                      store.loadShop(search: q);
                                    },
                                  ),
                                ),
                                if (widget.searchController.text.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchDebounce?.cancel();
                                      widget.searchController.clear();
                                    },
                                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                                  ),
                                Tooltip(
                                  message: 'Search by photo',
                                  child: IconButton(
                                    onPressed: store.loadingShop ? null : () => _pickImageSearch(context),
                                    icon: const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Material(
                                    color: AppColors.accent,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      onTap: store.loadingShop
                                          ? null
                                          : () {
                                              _searchDebounce?.cancel();
                                              store.loadShop(search: widget.searchController.text);
                                            },
                                      borderRadius: BorderRadius.circular(10),
                                      child: const SizedBox(
                                        width: 44,
                                        height: 40,
                                        child: Icon(Icons.arrow_forward_rounded, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (store.imageSearchActive) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.ringOrange.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: store.imageSearchPreview != null &&
                                            store.imageSearchPreview!.startsWith('data:')
                                        ? Image.memory(
                                            Uri.parse(store.imageSearchPreview!).data!.contentAsBytes(),
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 44,
                                            height: 44,
                                            color: Colors.white,
                                            child: const Icon(Icons.image_search, color: AppColors.accent),
                                          ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Image search', style: TextStyle(fontWeight: FontWeight.w800)),
                                        Text(
                                          store.imageSearchKeywords.isNotEmpty
                                              ? store.imageSearchKeywords.take(4).join(' · ')
                                              : '${store.products.length} similar product(s)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: store.clearImageSearch,
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('In Ghana'),
                          selected: store.filterInGhana,
                          onSelected: (_) => store.toggleInGhana(),
                          selectedColor: AppColors.emerald.withValues(alpha: 0.15),
                          checkmarkColor: AppColors.emerald,
                        ),
                        FilterChip(
                          label: const Text('Free Delivery'),
                          selected: store.filterFreeShip,
                          onSelected: (_) => store.toggleFreeShip(),
                          selectedColor: AppColors.blue.withValues(alpha: 0.12),
                          checkmarkColor: AppColors.blue,
                        ),
                        if (store.selectedCategoryId != null)
                          ActionChip(
                            label: const Text('Clear category'),
                            onPressed: store.clearCategoryFilter,
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _MatchesForRecentViews(key: ValueKey(_matchesTick))),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      store.imageSearchActive
                          ? '${store.products.length} image matches'
                          : '${store.products.length} results'
                              '${store.searchQuery.isNotEmpty ? ' · “${store.searchQuery}”' : ''}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (store.loadingShop && store.products.isEmpty)
                  const SliverFillRemaining(child: FullPageLoader(label: 'Loading products…'))
                else if (store.shopError != null && store.products.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(store.shopError!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => store.loadShop(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.66,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => ProductCard(product: store.products[index]),
                        childCount: store.products.length,
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

class _TopBar extends StatelessWidget {
  const _TopBar({this.user, required this.onOpenBrandHome});
  final AppUser? user;
  final Future<void> Function() onOpenBrandHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Tooltip(
            message: user == null
                ? 'Sign in'
                : (user!.role == 'seller'
                    ? 'Seller Centre'
                    : user!.role == 'admin'
                        ? 'Admin Dashboard'
                        : 'Home'),
            child: InkWell(
              onTap: () => onOpenBrandHome(),
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: BrandMark(height: 32),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  if (user == null) {
                    context.push('/login');
                    return;
                  }
                  context.push('/qr');
                },
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 20, color: AppColors.accent),
                label: const Text(
                  'Scan',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
          if (user != null)
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => context.push('/notifications'),
              icon: Badge(
                isLabelVisible: context.watch<AppStore>().unreadNotifications > 0,
                label: Text(
                  '${context.watch<AppStore>().unreadNotifications > 9 ? '9+' : context.watch<AppStore>().unreadNotifications}',
                ),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          IconButton(
            tooltip: 'Cart',
            onPressed: () {
              if (user == null) {
                context.push('/login');
                return;
              }
              context.push('/cart');
            },
            icon: Badge(
              isLabelVisible: context.watch<AppStore>().cartCount > 0,
              label: Text('${context.watch<AppStore>().cartCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          if (user == null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                height: 36,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => context.push('/login'),
                  child: const Text('Login'),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.accent,
                child: Text(
                  user!.name.isNotEmpty ? user!.name[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              "Ghana's Trusted Marketplace",
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Shop Ghana's Best Deals",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 8),
          Text(
            'Electronics, fashion, and more — delivered to your doorstep.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: const [
                _TrustChip(icon: Icons.verified_user_outlined, label: 'Verified Sellers'),
                SizedBox(width: 8),
                _TrustChip(icon: Icons.local_shipping_outlined, label: 'Fast Delivery'),
                SizedBox(width: 8),
                _TrustChip(icon: Icons.shield_outlined, label: 'Buyer Protection'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CategoryShortcuts extends StatelessWidget {
  const _CategoryShortcuts({required this.store});
  final AppStore store;

  IconData _iconFor(ShopCategory c) {
    final key = '${c.slug} ${c.name}'.toLowerCase();
    if (key.contains('phone') || key.contains('tablet')) return Icons.smartphone;
    if (key.contains('computer') || key.contains('laptop')) return Icons.laptop_mac;
    if (key.contains('electronic')) return Icons.devices_other;
    if (key.contains('vehicle') || key.contains('car')) return Icons.directions_car;
    if (key.contains('home') || key.contains('garden')) return Icons.home_outlined;
    return Icons.category_outlined;
  }

  Color _bg(int i) {
    const colors = [
      Color(0xFFFCE7F3),
      Color(0xFFE0F2FE),
      Color(0xFFFEF3C7),
      Color(0xFFD1FAE5),
      Color(0xFFEDE9FE),
      Color(0xFFFFEDD5),
    ];
    return colors[i % colors.length];
  }

  Color _fg(int i) {
    const colors = [
      Color(0xFFDB2777),
      Color(0xFF0284C7),
      Color(0xFFD97706),
      Color(0xFF059669),
      Color(0xFF7C3AED),
      Color(0xFFEA580C),
    ];
    return colors[i % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final items = <_Shortcut>[
      _Shortcut(
        label: 'Wish List',
        icon: Icons.favorite,
        bg: const Color(0xFFFCE7F3),
        fg: const Color(0xFFDB2777),
        onTap: () {
          if (!store.isLoggedIn) {
            context.push('/login');
            return;
          }
          context.push('/wishlist');
        },
      ),
      _Shortcut(
        label: 'In Ghana',
        icon: Icons.location_on,
        bg: const Color(0xFFD1FAE5),
        fg: AppColors.emerald,
        active: store.filterInGhana,
        onTap: store.toggleInGhana,
      ),
      _Shortcut(
        label: 'New Arrival',
        icon: Icons.auto_awesome,
        bg: const Color(0xFFFFEDD5),
        fg: AppColors.accent,
        onTap: () => store.loadShop(sortBy: 'newest'),
      ),
      _Shortcut(
        label: 'Free Delivery',
        icon: Icons.local_shipping,
        bg: const Color(0xFFE0F2FE),
        fg: AppColors.blue,
        active: store.filterFreeShip,
        onTap: store.toggleFreeShip,
      ),
      ...store.categories.asMap().entries.map(
            (e) => _Shortcut(
              label: e.value.name,
              icon: _iconFor(e.value),
              bg: _bg(e.key),
              fg: _fg(e.key),
              count: e.value.productsCount,
              active: store.selectedCategoryId == e.value.id,
              onTap: () => store.loadShop(categoryId: e.value.id),
            ),
          ),
    ];

    return SizedBox(
      height: 108,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final item = items[i];
          return InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 76,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: item.bg,
                      shape: BoxShape.circle,
                      border: item.active ? Border.all(color: item.fg, width: 2) : null,
                    ),
                    child: Icon(item.icon, color: item.fg, size: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: item.active ? item.fg : AppColors.textPrimary,
                    ),
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

class _Shortcut {
  _Shortcut({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.count,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final int? count;
  final bool active;
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Horizontal “Live now” stores — same idea as web home.
class _LiveNowStrip extends StatefulWidget {
  const _LiveNowStrip({super.key});

  @override
  State<_LiveNowStrip> createState() => _LiveNowStripState();
}

class _LiveNowStripState extends State<_LiveNowStrip> {
  List<LivestreamCard> _lives = const [];
  bool _loaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LiveNowStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final items = await context.read<AppStore>().fetchLiveNow();
      if (!mounted) return;
      setState(() {
        _lives = items;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _lives.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE NOW',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _lives.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final live = _lives[i];
                final photo = ApiConfig.resolveMediaUrl(live.shopPhoto);
                return InkWell(
                  onTap: () => context.push('/live/${live.storeSlug}'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 132,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (photo.isNotEmpty)
                                CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover)
                              else
                                Container(
                                  color: const Color(0xFFF3F4F6),
                                  alignment: Alignment.center,
                                  child: Text(
                                    live.storeName.isNotEmpty ? live.storeName[0].toUpperCase() : 'S',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 28,
                                      color: Color(0xFFD1D5DB),
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                live.storeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                              Text(
                                (live.title ?? '').trim().isNotEmpty ? live.title! : 'Live from the store',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal “Matches for recent views” strip — same idea as web home.
class _MatchesForRecentViews extends StatefulWidget {
  const _MatchesForRecentViews({super.key});

  @override
  State<_MatchesForRecentViews> createState() => _MatchesForRecentViewsState();
}

class _MatchesForRecentViewsState extends State<_MatchesForRecentViews> {
  List<RecentViewMatch> _products = const [];
  bool _loaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MatchesForRecentViews oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent bumps ValueKey(_matchesTick) on refresh / tab revisit.
    if (oldWidget.key != widget.key) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final items = await context.read<AppStore>().fetchMatchesForRecentViews();
      if (!mounted) return;
      setState(() {
        _products = items;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Keep prior products if a refresh fails so the strip does not vanish.
        _loaded = true;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: SizedBox(height: 168),
      );
    }
    if (_products.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Matches for recent views',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = _products[index];
                  final sellers = item.sellersInCategory < 1 ? 1 : item.sellersInCategory;
                  final image = ApiConfig.resolveMediaUrl(item.imageUrl);
                  return InkWell(
                    onTap: () {
                      unawaited(
                        RecentViews.record(id: item.id, categoryId: item.categoryId),
                      );
                      context.push('/products/${item.slug}');
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 110,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFF8FAFC), Color(0xFFFFF7ED)],
                                ),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: image.isEmpty
                                  ? const Icon(Icons.image_outlined, color: AppColors.textMuted)
                                  : CachedNetworkImage(
                                      imageUrl: image,
                                      fit: BoxFit.contain,
                                      errorWidget: (_, __, ___) =>
                                          const Icon(Icons.image_outlined, color: AppColors.textMuted),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$sellers ${sellers == 1 ? 'seller' : 'sellers'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          Text(
                            'From ${_money.format(item.fromPrice)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        product.discountPrice != null && product.discountPrice! < product.price;
    final pct = hasDiscount
        ? (((1 - product.discountPrice! / product.price) * 100).round())
        : 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () {
          unawaited(context.read<AppStore>().recordProductView(product));
          context.push('/products/${product.slug}');
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: const Color(0xFFF8FAFC),
                      padding: const EdgeInsets.all(10),
                      child: product.primaryImageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: product.primaryImageUrl!,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                ),
                              ),
                              errorWidget: (_, __, ___) =>
                                  const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
                            )
                          : const Icon(Icons.image_outlined, size: 40, color: AppColors.textMuted),
                    ),
                    if (hasDiscount)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-$pct%',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    if (product.freeShipping)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.emerald,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_shipping, size: 11, color: Colors.white),
                              SizedBox(width: 3),
                              Text('Free', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 1,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () async {
                            final store = context.read<AppStore>();
                            if (!store.isLoggedIn) {
                              context.push('/login');
                              return;
                            }
                            try {
                              final on = await store.toggleWishlist(product.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(on ? 'Saved to wishlist' : 'Removed from wishlist')),
                                );
                              }
                            } on ApiException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              context.watch<AppStore>().wishlistProductIds.contains(product.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 16,
                              color: context.watch<AppStore>().wishlistProductIds.contains(product.id)
                                  ? AppColors.danger
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    if (product.storeName != null)
                      Text(
                        'Sold by ${product.storeName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      _money.format(product.effectivePrice),
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (hasDiscount)
                      Text(
                        _money.format(product.price),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          decoration: TextDecoration.lineThrough,
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (product.rating > 0) ...[
                          const Icon(Icons.star, size: 12, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            product.rating.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Icon(Icons.visibility_outlined, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Text('${product.views}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        if (product.shipsNationwide) ...[
                          const SizedBox(width: 6),
                          Text('Nationwide', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600, fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountSettingsTab extends StatefulWidget {
  const AccountSettingsTab({super.key, this.user});
  final AppUser? user;

  @override
  State<AccountSettingsTab> createState() => _AccountSettingsTabState();
}

class _AccountSettingsTabState extends State<AccountSettingsTab> with AutoRefreshTab {
  @override
  int? get tabIndex => 4;

  @override
  Future<void> refreshTabData({required bool background}) async {
    final store = context.read<AppStore>();
    await store.refreshMe();
    await store.refreshNotificationCounts();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppStore>().user ?? widget.user;

    if (user == null) {
      if (tabIsWarmingUp) return const FullPageLoader(label: 'Loading your account…');

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(height: 40),
              const SizedBox(height: 16),
              const Text(
                'Sign in to manage your account',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Orders, wallet, wishlist, and addresses live here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Login'),
              ),
              TextButton(
                onPressed: () => context.push('/register'),
                child: const Text('Create shopper account'),
              ),
            ],
          ),
        ),
      );
    }

    final role = (user.role ?? '').toLowerCase();
    final links = <(IconData, String, String, String)>[
      if (role == 'seller')
        (Icons.dashboard_outlined, 'Seller Centre', 'Open your seller dashboard', '__seller_dashboard__'),
      if (role == 'admin')
        (Icons.admin_panel_settings_outlined, 'Admin Dashboard', 'Open admin centre', '__admin_dashboard__'),
      (Icons.notifications_outlined, 'Notifications', 'Orders, messages & updates', '/notifications'),
      (Icons.notifications_active_outlined, 'Allow phone alerts', 'Turn on popup notifications', '__enable_push__'),
      (Icons.person_outline, 'Profile settings', 'Photo & account details', '/profile/edit'),
      (Icons.qr_code_2_rounded, 'My namecard', 'Your QR to get paid & add friends', '/qr/receive'),
      (Icons.location_on_outlined, 'Addresses', 'Saved delivery addresses', '/addresses'),
      (Icons.favorite_border, 'Wishlist', 'Saved products', '/wishlist'),
      (Icons.storefront_outlined, 'Following', 'Sellers you follow', '/following'),
      (Icons.pin_outlined, 'Payment PIN', '4-digit code for wallet & transfers', '/profile/payment-pin'),
      (Icons.lock_outline, 'Change password', 'Account security', '/profile/password'),
      (Icons.shopping_cart_outlined, 'My cart', 'Review items before checkout', '/cart'),
    ];

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: refreshNow,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              BuyerProfileAvatar(
                name: user.name,
                avatar: user.avatar,
                radius: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(user.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    if (user.mobile != null)
                      Text(user.mobile!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.ringOrange,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Buyer',
                        style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (final item in links)
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.ringOrange,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Icon(item.$1, color: AppColors.accent, size: 18),
                  ),
                  title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(item.$3, style: const TextStyle(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.$4 == '/notifications' &&
                          context.watch<AppStore>().unreadNotifications > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${context.watch<AppStore>().unreadNotifications > 9 ? '9+' : context.watch<AppStore>().unreadNotifications}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    ],
                  ),
                  onTap: () async {
                    if (item.$4 == '__enable_push__') {
                      final granted = await PushNotifications.instance.requestPermission(
                        openSettingsIfDenied: true,
                      );
                      if (!context.mounted) return;
                      if (granted) {
                        await PushNotifications.instance.syncForLoggedInUser();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Phone notifications enabled')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Allow notifications in phone settings to get popups'),
                          ),
                        );
                      }
                      return;
                    }
                    if (item.$4 == '__seller_dashboard__' || item.$4 == '__admin_dashboard__') {
                      final base = ApiConfig.webBaseUrl.endsWith('/')
                          ? ApiConfig.webBaseUrl.substring(0, ApiConfig.webBaseUrl.length - 1)
                          : ApiConfig.webBaseUrl;
                      final path = item.$4 == '__admin_dashboard__'
                          ? '/admin/dashboard'
                          : '/seller/dashboard';
                      final uri = Uri.parse('$base$path');
                      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not open $path')),
                        );
                      }
                      return;
                    }
                    context.push(item.$4);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: Color(0xFFFECACA)),
            backgroundColor: Colors.white,
          ),
          onPressed: () async {
            final store = context.read<AppStore>();
            final messenger = ScaffoldMessenger.of(context);
            await PushNotifications.instance.clearForLogout();
            await store.logout();
            messenger.showSnackBar(
              const SnackBar(content: Text('Logged out')),
            );
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
      ),
    );
  }
}
