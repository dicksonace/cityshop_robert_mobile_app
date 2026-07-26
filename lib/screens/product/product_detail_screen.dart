import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? product;
  String? error;
  bool loading = true;
  bool adding = false;
  bool wishBusy = false;
  int qty = 1;
  int imageIndex = 0;

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
      final p = await context.read<AppStore>().fetchProduct(widget.slug);
      if (!mounted) return;
      setState(() {
        product = p;
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

  Future<void> _addToCart({bool goCheckout = false}) async {
    final store = context.read<AppStore>();
    final p = product;
    if (p == null) return;
    if (!store.isLoggedIn) {
      context.push('/login');
      return;
    }
    setState(() => adding = true);
    try {
      await store.addToCart(p.id, quantity: qty);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goCheckout ? 'Added — continue to checkout' : 'Added to cart'),
          action: SnackBarAction(
            label: 'Cart',
            onPressed: () => context.push('/cart'),
          ),
        ),
      );
      if (goCheckout) context.push('/cart');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  Future<void> _toggleWish() async {
    final store = context.read<AppStore>();
    final p = product;
    if (p == null) return;
    if (!store.isLoggedIn) {
      context.push('/login');
      return;
    }
    setState(() => wishBusy = true);
    try {
      final on = await store.toggleWishlist(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(on ? 'Saved to wishlist' : 'Removed from wishlist')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => wishBusy = false);
    }
  }

  Future<void> _messageSeller() async {
    final store = context.read<AppStore>();
    final p = product;
    if (p == null || p.sellerId == null) return;
    if (!store.isLoggedIn) {
      context.push('/login');
      return;
    }
    try {
      final result = await store.openConversation(sellerId: p.sellerId!, productId: p.id);
      if (!mounted) return;
      context.push('/messages/${result.conversation.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final loggedIn = store.isLoggedIn;
    final p = product;
    final wishlisted = p != null && store.wishlistProductIds.contains(p.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(p?.name ?? 'Product'),
        actions: [
          IconButton(
            onPressed: wishBusy ? null : _toggleWish,
            icon: Icon(wishlisted ? Icons.favorite : Icons.favorite_border, color: wishlisted ? AppColors.danger : null),
          ),
          IconButton(
            onPressed: () => context.push('/cart'),
            icon: Badge(
              isLabelVisible: store.cartCount > 0,
              label: Text('${store.cartCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading product…')
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _Body(
                  product: p!,
                  imageIndex: imageIndex,
                  qty: qty,
                  onImageChanged: (i) => setState(() => imageIndex = i),
                  onQtyChanged: (q) => setState(() => qty = q),
                  onMessage: _messageSeller,
                ),
      bottomNavigationBar: p == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: loggedIn ? () => _addToCart() : () => context.push('/login'),
                        child: Text(loggedIn ? 'Add to cart' : 'Login'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: loggedIn ? 'Buy now' : 'Login to buy',
                        loading: adding,
                        onPressed: adding
                            ? null
                            : () => loggedIn ? _addToCart(goCheckout: true) : context.push('/login'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.product,
    required this.imageIndex,
    required this.qty,
    required this.onImageChanged,
    required this.onQtyChanged,
    required this.onMessage,
  });

  final Product product;
  final int imageIndex;
  final int qty;
  final ValueChanged<int> onImageChanged;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final images = product.images;
    final image = images.isNotEmpty
        ? images[imageIndex.clamp(0, images.length - 1)].url
        : product.primaryImageUrl;
    final hasDiscount =
        product.discountPrice != null && product.discountPrice! < product.price;

    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: image != null
                ? CachedNetworkImage(imageUrl: image, fit: BoxFit.contain)
                : const Icon(Icons.image, size: 64, color: AppColors.textMuted),
          ),
        ),
        if (images.length > 1)
          SizedBox(
            height: 72,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == imageIndex;
                return GestureDetector(
                  onTap: () => onImageChanged(i),
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: images[i].url, fit: BoxFit.cover),
                    ),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.categoryName != null)
                Text(
                  product.categoryName!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                product.name,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money.format(product.effectivePrice),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                  if (hasDiscount) ...[
                    const SizedBox(width: 8),
                    Text(
                      _money.format(product.price),
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              if (product.storeName != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Sold by ${product.storeName}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (product.inGhana)
                    Chip(
                      label: const Text('In Ghana'),
                      backgroundColor: AppColors.emerald.withValues(alpha: 0.12),
                      side: BorderSide.none,
                    ),
                  if (product.freeShipping)
                    Chip(
                      avatar: const Icon(Icons.local_shipping, size: 16, color: AppColors.emerald),
                      label: const Text('Free delivery'),
                      backgroundColor: AppColors.emerald.withValues(alpha: 0.12),
                      side: BorderSide.none,
                    ),
                  if (product.isPreorder)
                    const Chip(label: Text('Pre-order'), side: BorderSide.none),
                  if (product.rating > 0)
                    Chip(
                      avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                      label: Text('${product.rating.toStringAsFixed(1)} (${product.reviewCount})'),
                      side: BorderSide.none,
                    ),
                  Chip(
                    label: Text('${product.quantity} in stock'),
                    side: BorderSide.none,
                    backgroundColor: const Color(0xFFF1F5F9),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: qty > 1 ? () => onQtyChanged(qty - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$qty', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    onPressed: qty < product.quantity || product.isPreorder
                        ? () => onQtyChanged(qty + 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              if (product.sellerId != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message seller'),
                ),
              ],
              const SizedBox(height: 16),
              if (product.brand != null && product.brand!.isNotEmpty) ...[
                Text('Brand: ${product.brand}', style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 12),
              ],
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                product.description?.trim().isNotEmpty == true
                    ? product.description!
                    : 'No description provided.',
                style: const TextStyle(height: 1.45, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
