import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';

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
        child: Column(
          children: [
            _Header(user: store.user),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _ShopHome(searchController: _search),
                  const _PlaceholderTab(
                    icon: Icons.favorite_border,
                    title: 'Wish List',
                    subtitle: 'Save items you love — coming next.',
                  ),
                  const _PlaceholderTab(
                    icon: Icons.receipt_long_outlined,
                    title: 'Orders',
                    subtitle: 'Track your purchases — coming next.',
                  ),
                  _AccountTab(user: store.user),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Shop'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Wish'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_city, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CityShop', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Text("Ghana's marketplace", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cart coming next — login to shop.')),
              );
            },
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
          if (user == null)
            TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('Login'),
            )
          else
            IconButton(
              onPressed: () {},
              icon: CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary,
                child: Text(
                  user!.name.isNotEmpty ? user!.name[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
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

    return RefreshIndicator(
      onRefresh: () => store.loadShop(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _HeroBanner()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        minimumSize: const Size(72, 48),
                      ),
                      onPressed: () => store.loadShop(search: searchController.text),
                      child: const Text('Search'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _QuickChip(
                    label: 'All',
                    selected: store.selectedCategoryId == null,
                    onTap: () => store.clearCategoryFilter(),
                  ),
                  ...store.categories.map(
                    (c) => _QuickChip(
                      label: c.name,
                      icon: c.icon,
                      count: c.productsCount,
                      selected: store.selectedCategoryId == c.id,
                      onTap: () => store.loadShop(categoryId: c.id),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${store.products.length} products'
                '${store.selectedCategoryId != null ? ' · filtered' : ''}'
                '${store.searchQuery.isNotEmpty ? ' · “${store.searchQuery}”' : ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (store.loadingShop && store.products.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
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
                  childAspectRatio: 0.68,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ProductCard(product: store.products[index]),
                  childCount: store.products.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Shop Ghana's Best Deals",
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
          ),
          SizedBox(height: 8),
          Text(
            'Electronics, fashion, and more — delivered to your doorstep.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
          ),
          SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrustPill(label: 'Verified Sellers'),
              _TrustPill(label: 'Fast Delivery'),
              _TrustPill(label: 'Buyer Protection'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon ?? '🛍️', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: selected ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
            ],
          ),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/products/${product.slug}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: product.primaryImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: product.primaryImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.border),
                      errorWidget: (_, __, ___) => const Center(child: Icon(Icons.image_not_supported_outlined)),
                    )
                  : Container(
                      color: AppColors.border,
                      child: const Icon(Icons.image_outlined, size: 40, color: AppColors.textSecondary),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.categoryName != null)
                    Text(
                      product.categoryName!.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  const SizedBox(height: 4),
                  if (product.storeName != null)
                    Text(
                      'Sold by ${product.storeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    _money.format(product.effectivePrice),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab({this.user});

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
              const Icon(Icons.person_outline, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              const Text('Sign in to manage your account', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Login'),
              ),
              TextButton(
                onPressed: () => context.push('/register'),
                child: const Text('Create account'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary,
            child: Text(user!.name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
          ),
          title: Text(user!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(user!.email),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: AppColors.danger),
          title: const Text('Log out'),
          onTap: () async {
            await context.read<AppStore>().logout();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged out')),
              );
            }
          },
        ),
      ],
    );
  }
}
