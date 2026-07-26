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
  List<Product> related = [];
  List<Map<String, dynamic>> reviews = [];
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
      final detail = await context.read<AppStore>().fetchProductDetail(widget.slug);
      if (!mounted) return;
      setState(() {
        product = detail.product;
        related = detail.related;
        reviews = detail.reviews;
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
          action: SnackBarAction(label: 'Cart', onPressed: () => context.push('/cart')),
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
            icon: Icon(
              wishlisted ? Icons.favorite : Icons.favorite_border,
              color: wishlisted ? AppColors.danger : null,
            ),
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
                  related: related,
                  reviews: reviews,
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
    required this.related,
    required this.reviews,
    required this.imageIndex,
    required this.qty,
    required this.onImageChanged,
    required this.onQtyChanged,
    required this.onMessage,
  });

  final Product product;
  final List<Product> related;
  final List<Map<String, dynamic>> reviews;
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
    final discountPct = hasDiscount
        ? (((1 - (product.discountPrice! / product.price)) * 100).round())
        : 0;

    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                child: image != null
                    ? CachedNetworkImage(imageUrl: image, fit: BoxFit.contain)
                    : const Icon(Icons.image, size: 64, color: AppColors.textMuted),
              ),
              if (hasDiscount)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '-$discountPct%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                ),
            ],
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
                      border: Border.all(
                        color: selected ? AppColors.accent : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
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
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    product.rating > 0
                        ? '${product.rating.toStringAsFixed(1)} (${product.reviewCount})'
                        : 'No ratings yet',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.visibility_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text('${product.views} views', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(width: 10),
                  Icon(Icons.favorite_border, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text('${product.wishlistAdds}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 14),
              _SellerCard(product: product, onMessage: onMessage),
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
                  if (product.shipsNationwide)
                    const Chip(label: Text('Ships nationwide'), side: BorderSide.none),
                  if (product.pickupAvailable)
                    const Chip(label: Text('Pickup available'), side: BorderSide.none),
                  if (product.isNegotiable)
                    const Chip(label: Text('Negotiable'), side: BorderSide.none),
                  if (product.isPreorder)
                    const Chip(label: Text('Pre-order'), side: BorderSide.none),
                  if (product.cashOnDelivery)
                    const Chip(label: Text('Cash on delivery'), side: BorderSide.none),
                  Chip(
                    label: Text('${product.quantity} in stock'),
                    side: BorderSide.none,
                    backgroundColor: const Color(0xFFF1F5F9),
                  ),
                ],
              ),
              if (product.deliveryFee != null || product.deliveryDays != null) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    if (product.deliveryFee != null) 'Delivery: ${_money.format(product.deliveryFee)}',
                    if (product.deliveryDays != null) '${product.deliveryDays} day(s)',
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
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
              const SizedBox(height: 16),
              if (product.brand != null && product.brand!.isNotEmpty)
                Text('Brand: ${product.brand}', style: const TextStyle(color: AppColors.textSecondary)),
              if (product.condition != null && product.condition!.isNotEmpty)
                Text('Condition: ${product.condition}', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                product.description?.trim().isNotEmpty == true
                    ? product.description!
                    : 'No description provided.',
                style: const TextStyle(height: 1.45, color: AppColors.textSecondary),
              ),
              if (product.specifications.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Specifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                ...product.specifications.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${e.key}',
                            style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (reviews.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('Reviews', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                ...reviews.take(5).map((r) {
                  final user = r['user'];
                  final name = user is Map ? (user['name'] as String? ?? 'Buyer') : 'Buyer';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text('★ ${(r['rating'] as num?)?.toStringAsFixed(1) ?? '-'}'),
                          ],
                        ),
                        if ((r['comment'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text('${r['comment']}', style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  );
                }),
              ],
              if (related.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('Related products', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 210,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: related.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = related[index];
                      final img = item.primaryImageUrl;
                      return InkWell(
                        onTap: () => context.push('/products/${item.slug}'),
                        child: Container(
                          width: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                  child: img != null
                                      ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
                                      : const ColoredBox(color: Color(0xFFF8FAFC), child: Icon(Icons.image)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                    Text(_money.format(item.effectivePrice), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
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
            ],
          ),
        ),
      ],
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.product, required this.onMessage});
  final Product product;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.ringOrange,
            backgroundImage: product.sellerPhoto != null ? CachedNetworkImageProvider(product.sellerPhoto!) : null,
            child: product.sellerPhoto == null
                ? Text(
                    (product.storeName ?? 'S').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sold by ${product.storeName ?? 'Seller'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (product.sellerRating != null || product.sellerSales != null)
                  Text(
                    [
                      if (product.sellerRating != null) '★ ${product.sellerRating!.toStringAsFixed(1)}',
                      if (product.sellerSales != null) '${product.sellerSales} sales',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (product.sellerId != null)
            OutlinedButton(
              onPressed: onMessage,
              child: const Text('Chat'),
            ),
        ],
      ),
    );
  }
}
