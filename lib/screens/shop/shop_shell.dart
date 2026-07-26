import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class ShopShell extends StatefulWidget {
  const ShopShell({super.key});

  @override
  State<ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends State<ShopShell> {
  final _search = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _ShopHome(searchController: _search),
            _ComingSoon(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet',
              subtitle: 'Top up and pay with your CityShop wallet — next.',
              actionLabel: store.isLoggedIn ? null : 'Login',
              onAction: store.isLoggedIn ? null : () => context.push('/login'),
            ),
            _ComingSoon(
              icon: Icons.inventory_2_outlined,
              title: 'My Orders',
              subtitle: 'Track purchases and confirm delivery — next.',
              actionLabel: store.isLoggedIn ? null : 'Login',
              onAction: store.isLoggedIn ? null : () => context.push('/login'),
            ),
            _ComingSoon(
              icon: Icons.chat_bubble_outline,
              title: 'Messages',
              subtitle: 'Chat with sellers — next.',
              actionLabel: store.isLoggedIn ? null : 'Login',
              onAction: store.isLoggedIn ? null : () => context.push('/login'),
            ),
            AccountSettingsTab(user: store.user),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AppColors.accent,
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
            icon: Icon(Icons.inventory_2_outlined, color: _tab == 2 ? Colors.white : AppColors.textSecondary),
            label: 'My Order',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline, color: _tab == 3 ? Colors.white : AppColors.textSecondary),
            label: 'Message',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: _tab == 4 ? Colors.white : AppColors.textSecondary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ShopHome extends StatelessWidget {
  const _ShopHome({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Column(
      children: [
        _TopBar(user: store.user),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => store.loadShop(),
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
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  decoration: const InputDecoration(
                                    hintText: 'Search products, stores, brands...',
                                    prefixIcon: Icon(Icons.search),
                                    isDense: true,
                                  ),
                                  onSubmitted: (q) => store.loadShop(search: q),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () => store.loadShop(search: searchController.text),
                                  child: const Text('Search'),
                                ),
                              ),
                            ],
                          ),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '${store.products.length} results'
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
  const _TopBar({this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          const BrandMark(height: 32),
          const Spacer(),
          IconButton(
            tooltip: 'Cart',
            onPressed: () {
              if (user == null) {
                context.push('/login');
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cart coming next')),
              );
            },
            icon: const Icon(Icons.shopping_cart_outlined),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wishlist coming next')),
          );
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
        onTap: () => context.push('/products/${product.slug}'),
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
                          onTap: () {
                            if (!context.read<AppStore>().isLoggedIn) {
                              context.push('/login');
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Wishlist coming next')),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.favorite_border, size: 16, color: AppColors.textSecondary),
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

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.ringOrange,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class AccountSettingsTab extends StatelessWidget {
  const AccountSettingsTab({super.key, this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
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

    final links = [
      (Icons.person_outline, 'Profile settings', 'Name & email'),
      (Icons.location_on_outlined, 'Addresses', 'Saved delivery addresses'),
      (Icons.favorite_border, 'Wishlist', 'Saved products'),
      (Icons.lock_outline, 'Change password', 'Account security'),
    ];

    return ListView(
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
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.accent,
                child: Text(
                  user!.name.isNotEmpty ? user!.name[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user!.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(user!.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    if (user!.mobile != null)
                      Text(user!.mobile!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${item.$2} — wiring next')),
                    );
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
            await context.read<AppStore>().logout();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged out')),
              );
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}
