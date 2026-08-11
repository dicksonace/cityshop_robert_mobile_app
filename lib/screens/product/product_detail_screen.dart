import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/image_viewer.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

String _specificationLabel(String key) {
  return key
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

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
  Map<String, dynamic>? reviewable;
  String? error;
  bool loading = true;
  bool adding = false;
  bool wishBusy = false;
  int qty = 1;
  bool showAddedToast = false;
  Timer? _addedToastTimer;

  /// Live like total — bumped locally on tap so the count does not wait on the API.
  int likeCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addedToastTimer?.cancel();
    super.dispose();
  }

  void _showAddedToast() {
    _addedToastTimer?.cancel();
    setState(() => showAddedToast = true);
    _addedToastTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => showAddedToast = false);
    });
  }

  void _hideAddedToast() {
    _addedToastTimer?.cancel();
    if (showAddedToast) setState(() => showAddedToast = false);
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final store = context.read<AppStore>();
      final detail = await store.fetchProductDetail(widget.slug);
      if (!mounted) return;
      unawaited(store.recordProductView(detail.product));
      setState(() {
        product = detail.product;
        related = detail.related;
        reviews = detail.reviews;
        reviewable = detail.reviewable;
        likeCount = detail.product.wishlistAdds;
        if (store.wishlistProductIds.contains(detail.product.id) && likeCount < 1) {
          likeCount = 1;
        }
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
      // Drop any leftover system snackbars that can stick around after rebuilds.
      ScaffoldMessenger.of(context).clearSnackBars();
      if (goCheckout) {
        _hideAddedToast();
        context.push('/cart');
        return;
      }
      _showAddedToast();
    } on ApiException catch (e) {
      if (!mounted) return;
      _hideAddedToast();
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  Future<void> _toggleWish() async {
    final store = context.read<AppStore>();
    final p = product;
    if (p == null || wishBusy) return;
    if (!store.isLoggedIn) {
      context.push('/login');
      return;
    }
    final wasLiked = store.wishlistProductIds.contains(p.id);
    wishBusy = true;
    setState(() {
      likeCount = wasLiked ? (likeCount - 1).clamp(0, 1 << 30) : likeCount + 1;
    });
    try {
      await store.toggleWishlist(p.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        likeCount = wasLiked ? likeCount + 1 : (likeCount - 1).clamp(0, 1 << 30);
      });
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
      context.push(
        '/messages/${result.conversation.id}',
        extra: result.attachProduct,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleFollowSeller() async {
    final p = product;
    final sellerId = p?.sellerId;
    if (sellerId == null) return;
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      context.push('/login');
      return;
    }
    try {
      final following = await store.toggleFollowSeller(sellerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(following ? 'Following this seller' : 'Unfollowed this seller'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {});
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _shareProduct() async {
    final p = product;
    final slug = p?.slug.isNotEmpty == true ? p!.slug : widget.slug;
    final url = ApiConfig.productShareUrl(slug);
    final name = p?.name.trim().isNotEmpty == true ? p!.name.trim() : 'this product';
    final price = p != null ? _money.format(p.price) : null;
    final buffer = StringBuffer('Check out $name on CityShop');
    if (price != null) buffer.write(' — $price');
    buffer.write('\n$url');
    await SharePlus.instance.share(
      ShareParams(text: buffer.toString(), subject: name),
    );
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
            onPressed: _toggleWish,
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
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              if (value == 'share') {
                await _shareProduct();
              } else if (value == 'follow') {
                await _toggleFollowSeller();
              }
            },
            itemBuilder: (context) {
              final sellerId = p?.sellerId;
              final following = sellerId != null && store.followingSellerIds.contains(sellerId);
              return [
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.share_outlined),
                    title: Text('Share this ad'),
                  ),
                ),
                if (sellerId != null)
                  PopupMenuItem(
                    value: 'follow',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(following ? Icons.person_remove_alt_1_outlined : Icons.person_add_alt_1_outlined),
                      title: Text(following ? 'Unfollow this seller' : 'Follow this seller'),
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: loading
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
                        reviewable: reviewable,
                        qty: qty,
                        likeCount: likeCount,
                        liked: wishlisted,
                        onQtyChanged: (q) => setState(() => qty = q),
                        onMessage: _messageSeller,
                        onReviewPosted: _load,
                      ),
          ),
          if (showAddedToast)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Material(
                elevation: 6,
                color: const Color(0xFF323232),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Added to cart',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _hideAddedToast();
                          context.push('/cart');
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Cart', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
    this.reviewable,
    required this.qty,
    required this.likeCount,
    required this.liked,
    required this.onQtyChanged,
    required this.onMessage,
    required this.onReviewPosted,
  });

  final Product product;
  final List<Product> related;
  final List<Map<String, dynamic>> reviews;
  final Map<String, dynamic>? reviewable;
  final int qty;
  final int likeCount;
  final bool liked;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onMessage;
  final Future<void> Function() onReviewPosted;

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        product.discountPrice != null && product.discountPrice! < product.price;
    final discountPct = hasDiscount
        ? (((1 - (product.discountPrice! / product.price)) * 100).round())
        : 0;

    return ListView(
      children: [
        _ProductImageGallery(
          images: product.images,
          fallbackUrl: product.primaryImageUrl,
          videoUrl: product.videoUrl,
          videoDuration: product.videoDuration,
          discountPct: hasDiscount ? discountPct : null,
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
                children: [
                  const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFBBF24)),
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
                  Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    size: 16,
                    color: liked ? AppColors.danger : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text('$likeCount likes', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _money.format(product.effectivePrice),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
              if (hasDiscount)
                Text(
                  _money.format(product.price),
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: AppColors.textMuted,
                  ),
                ),
              const SizedBox(height: 14),
              _DeliveryPickupCard(product: product),
              const SizedBox(height: 12),
              _SellerCard(product: product, onMessage: onMessage),
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
              if (product.condition != null && product.condition!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Condition: ${product.condition}', style: const TextStyle(color: AppColors.textSecondary)),
              ],
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
                            _specificationLabel(e.key),
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
              const SizedBox(height: 22),
              _ProductReviews(
                reviews: reviews,
                reviewable: reviewable,
                onPosted: onReviewPosted,
              ),
              if (related.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('Related products', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: related.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.62,
                  ),
                  itemBuilder: (context, index) {
                    final item = related[index];
                    final img = item.primaryImageUrl;
                    return InkWell(
                      onTap: () {
                        unawaited(context.read<AppStore>().recordProductView(item));
                        context.push('/products/${item.slug}');
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
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
                                    : const ColoredBox(
                                        color: Color(0xFFF8FAFC),
                                        child: Icon(Icons.image),
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _money.format(item.effectivePrice),
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w800,
                                    ),
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
              ],
            ],
          ),
        ),
      ],
    );
  }
}

final _reviewDate = DateFormat('d MMM yyyy');

class _ProductReviews extends StatefulWidget {
  const _ProductReviews({
    required this.reviews,
    this.reviewable,
    required this.onPosted,
  });

  final List<Map<String, dynamic>> reviews;
  final Map<String, dynamic>? reviewable;
  final Future<void> Function() onPosted;

  @override
  State<_ProductReviews> createState() => _ProductReviewsState();
}

class _ProductReviewsState extends State<_ProductReviews> {
  final _comment = TextEditingController();
  int _rating = 5;
  bool _posting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  String _formatDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    return _reviewDate.format(parsed.toLocal());
  }

  Future<void> _post() async {
    final reviewable = widget.reviewable;
    if (reviewable == null) return;
    final orderId = (reviewable['order_id'] as num?)?.toInt() ?? 0;
    final itemId = (reviewable['order_item_id'] as num?)?.toInt() ?? 0;
    final comment = _comment.text.trim();
    if (orderId < 1 || itemId < 1) return;
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a comment before posting your review.')),
      );
      return;
    }
    setState(() => _posting = true);
    try {
      await context.read<AppStore>().submitReview(
            orderId: orderId,
            orderItemId: itemId,
            rating: _rating,
            comment: comment,
          );
      if (!mounted) return;
      _comment.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your review!')),
      );
      await widget.onPosted();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Widget _stars(int rating, {double size = 16, ValueChanged<int>? onChanged}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: onChanged == null ? null : () => onChanged(i),
            child: Icon(
              i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i <= rating ? const Color(0xFFFBBF24) : const Color(0xFFE5E7EB),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AppStore>().isLoggedIn;
    final reviews = widget.reviews;
    final average = reviews.isEmpty
        ? 0.0
        : reviews.fold<double>(0, (sum, r) => sum + ((r['rating'] as num?)?.toDouble() ?? 0)) /
            reviews.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Customer Reviews & Ratings',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (reviews.isNotEmpty) ...[
                _stars(average.round()),
                const SizedBox(width: 6),
                Text(
                  '${average.toStringAsFixed(1)} · ${reviews.length}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Rate with stars and leave a written comment after your order is delivered.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
          ),
          if (loggedIn && widget.reviewable != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFED7AA), width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Write your review', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                    'You purchased this item — tap stars to rate, then add your comment.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _stars(_rating, size: 28, onChanged: (n) => setState(() => _rating = n)),
                      const SizedBox(width: 8),
                      Text(
                        '$_rating/5',
                        style: const TextStyle(
                          color: Color(0xFFD97706),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _comment,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'Share your experience — quality, delivery, would you recommend it?',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _posting ? null : _post,
                      child: Text(_posting ? 'Posting…' : 'Post Review'),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (loggedIn) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How to leave a review', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                    '1. Buy this product and complete checkout\n'
                    '2. Wait until the seller marks your order as Delivered\n'
                    '3. Come back here — a star rating and comment box will appear',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  TextButton(
                    onPressed: () => context.go('/shop?tab=orders'),
                    child: const Text('View your orders →'),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.push('/login'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text.rich(
                  TextSpan(
                    text: 'Sign in',
                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                    children: [
                      TextSpan(
                        text: ' to leave a review after purchase.',
                        style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No reviews yet. Be the first to share your experience!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...reviews.map((r) {
              final user = r['user'];
              final name = user is Map ? (user['name'] as String? ?? 'Customer') : 'Customer';
              final rating = (r['rating'] as num?)?.round() ?? 0;
              final comment = (r['comment'] as String?)?.trim() ?? '';
              final date = _formatDate(r['created_at']);
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _stars(rating),
                        if (date.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(date, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        comment,
                        style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _GalleryItem {
  const _GalleryItem.image(this.url) : isVideo = false;
  const _GalleryItem.video(this.url) : isVideo = true;

  final String url;
  final bool isVideo;
}

class _ProductImageGallery extends StatefulWidget {
  const _ProductImageGallery({
    required this.images,
    this.fallbackUrl,
    this.videoUrl,
    this.videoDuration,
    this.discountPct,
  });

  final List<ProductImage> images;
  final String? fallbackUrl;
  final String? videoUrl;
  final int? videoDuration;
  final int? discountPct;

  @override
  State<_ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<_ProductImageGallery> {
  late final PageController _pageController;
  final ScrollController _thumbsController = ScrollController();
  int _index = 0;
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _muted = false;

  List<_GalleryItem> get _items {
    final items = <_GalleryItem>[];
    for (final image in widget.images) {
      final url = ApiConfig.resolveMediaUrl(image.url);
      if (url.isNotEmpty) items.add(_GalleryItem.image(url));
    }
    if (items.isEmpty) {
      final fallback = ApiConfig.resolveMediaUrl(widget.fallbackUrl);
      if (fallback.isNotEmpty) items.add(_GalleryItem.image(fallback));
    }
    // Product video last (same as web gallery).
    final video = ApiConfig.resolveMediaUrl(widget.videoUrl);
    if (video.isNotEmpty) {
      items.add(_GalleryItem.video(video));
    }
    return items;
  }

  String? get _posterUrl {
    for (final image in widget.images) {
      final url = ApiConfig.resolveMediaUrl(image.url);
      if (url.isNotEmpty) return url;
    }
    return ApiConfig.resolveMediaUrl(widget.fallbackUrl).isEmpty
        ? null
        : ApiConfig.resolveMediaUrl(widget.fallbackUrl);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbsController.dispose();
    _disposeVideo();
    super.dispose();
  }

  void _disposeVideo() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _videoController = null;
    _videoReady = false;
    _videoFailed = false;
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  Future<void> _ensureVideo() async {
    final items = _items;
    if (_index >= items.length || !items[_index].isVideo) return;
    final url = items[_index].url;
    if (_videoController != null && _videoController!.dataSource == url && _videoReady) {
      return;
    }
    _disposeVideo();
    setState(() {
      _videoFailed = false;
      _videoReady = false;
    });
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = controller;
      controller.addListener(_onVideoTick);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted) return;
      setState(() => _videoReady = true);
      await controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoFailed = true);
    }
  }

  void _goTo(int i) {
    final total = _items.length;
    if (total == 0) return;
    final next = ((i % total) + total) % total;
    setState(() => _index = next);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
    _scrollThumbIntoView(next);
    if (_items[next].isVideo) {
      _ensureVideo();
    } else {
      _videoController?.pause();
    }
  }

  void _scrollThumbIntoView(int i) {
    if (!_thumbsController.hasClients) return;
    const itemWidth = 72.0;
    final target = (i * itemWidth) - 40;
    _thumbsController.animateTo(
      target.clamp(0.0, _thumbsController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  String _durationLabel() {
    final seconds = widget.videoDuration;
    if (seconds == null || seconds <= 0) return 'Video';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return 'Video · $m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePlay() async {
    final c = _videoController;
    if (c == null || !_videoReady) {
      await _ensureVideo();
      return;
    }
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _videoController?.setVolume(_muted ? 0 : 1);
  }

  /// Opens the viewer on the photo at gallery position [galleryIndex]. The
  /// video pane keeps its own tap handling, so it is left out of the viewer.
  void _openFullScreen(int galleryIndex) {
    final items = _items;
    final urls = <String>[];
    var initialIndex = 0;

    for (var i = 0; i < items.length; i++) {
      if (items[i].isVideo) continue;
      if (i == galleryIndex) initialIndex = urls.length;
      urls.add(items[i].url);
    }

    _videoController?.pause();
    showImageViewer(context, urls: urls, initialIndex: initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final total = items.length;
    final currentIsVideo = total > 0 && items[_index].isVideo;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                child: total == 0
                    ? const Icon(Icons.image, size: 64, color: AppColors.textMuted)
                    : PageView.builder(
                        controller: _pageController,
                        itemCount: total,
                        onPageChanged: (i) {
                          setState(() => _index = i);
                          _scrollThumbIntoView(i);
                          if (items[i].isVideo) {
                            _ensureVideo();
                          } else {
                            _videoController?.pause();
                          }
                        },
                        itemBuilder: (context, i) {
                          final item = items[i];
                          if (item.isVideo) {
                            return _buildVideoPane();
                          }
                          return GestureDetector(
                            onTap: () => _openFullScreen(i),
                            child: CachedNetworkImage(
                              imageUrl: item.url,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const Center(child: AppLoader()),
                              errorWidget: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined, size: 48, color: AppColors.textMuted),
                            ),
                          );
                        },
                      ),
              ),
              if (widget.discountPct != null)
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
                      '-${widget.discountPct}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                ),
              if (currentIsVideo)
                Positioned(
                  top: 12,
                  left: widget.discountPct != null ? 72 : 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _durationLabel(),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              if (total > 1) ...[
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryNavButton(
                      icon: Icons.chevron_left,
                      onTap: () => _goTo(_index - 1),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryNavButton(
                      icon: Icons.chevron_right,
                      onTap: () => _goTo(_index + 1),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(total, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active ? AppColors.accent : Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_index + 1}/$total',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (total > 1)
          SizedBox(
            height: 84,
            child: ListView.separated(
              controller: _thumbsController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              scrollDirection: Axis.horizontal,
              itemCount: total,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == _index;
                final item = items[i];
                return GestureDetector(
                  onTap: () => _goTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? AppColors.accent : AppColors.border,
                        width: selected ? 2.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.25),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (item.isVideo)
                            (_posterUrl != null
                                ? CachedNetworkImage(imageUrl: _posterUrl!, fit: BoxFit.cover)
                                : Container(color: Colors.black87))
                          else
                            CachedNetworkImage(imageUrl: item.url, fit: BoxFit.cover),
                          if (item.isVideo)
                            Container(
                              color: Colors.black.withValues(alpha: 0.35),
                              child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildVideoPane() {
    if (_videoFailed) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_outlined, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 8),
          const Text('Could not load video', style: TextStyle(color: AppColors.textSecondary)),
          TextButton(onPressed: _ensureVideo, child: const Text('Retry')),
        ],
      );
    }

    if (!_videoReady || _videoController == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_posterUrl != null)
            CachedNetworkImage(imageUrl: _posterUrl!, fit: BoxFit.contain)
          else
            Container(color: Colors.black),
          const Center(child: AppLoader()),
        ],
      );
    }

    final playing = _videoController!.value.isPlaying;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio == 0
                  ? 1
                  : _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _togglePlay,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: playing ? 0 : 1,
                child: Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 14,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: _muted ? 'Unmute' : 'Mute',
              onPressed: _toggleMute,
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _GalleryNavButton extends StatelessWidget {
  const _GalleryNavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _DeliveryPickupCard extends StatelessWidget {
  const _DeliveryPickupCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final description = product.description?.trim();
    final paidDelivery = !product.freeShipping && product.deliveryFee != null && product.deliveryFee! > 0;
    final days = product.deliveryDays;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FAFC), Colors.white],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (description != null && description.isNotEmpty)
                      ? description
                      : 'No description provided.',
                  style: TextStyle(
                    height: 1.45,
                    fontSize: 15,
                    color: (description != null && description.isNotEmpty)
                        ? const Color(0xFF334155)
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (product.brand != null && product.brand!.isNotEmpty)
                      _pill(
                        label: 'Brand · ${product.brand}',
                        background: Colors.white,
                        foreground: const Color(0xFF334155),
                        border: const Color(0xFFE2E8F0),
                      ),
                    _pill(
                      icon: Icons.inventory_2_outlined,
                      label: product.quantity > 0 ? '${product.quantity} in stock' : 'Out of stock',
                      background: product.quantity > 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                      foreground: product.quantity > 0 ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                      border: product.quantity > 0 ? const Color(0xFFD1FAE5) : const Color(0xFFFECACA),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'DELIVERY & PICKUP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
                if (product.freeShipping)
                  const _ServiceRow(
                    icon: Icons.local_shipping_outlined,
                    iconBackground: Color(0xFFD1FAE5),
                    iconColor: Color(0xFF059669),
                    background: Color(0xFFECFDF5),
                    border: Color(0xFFA7F3D0),
                    title: 'Free delivery',
                    subtitle: 'Seller covers shipping to you',
                    titleColor: Color(0xFF065F46),
                    subtitleColor: Color(0xFF047857),
                  )
                else if (paidDelivery)
                  _ServiceRow(
                    icon: Icons.local_shipping_outlined,
                    iconBackground: const Color(0xFFE0F2FE),
                    iconColor: const Color(0xFF0284C7),
                    background: const Color(0xFFF0F9FF),
                    border: const Color(0xFFBAE6FD),
                    title: 'Paid delivery: ${_money.format(product.deliveryFee)}',
                    subtitle: days != null
                        ? 'Delivery Time: ${days}day${days == 1 ? '' : 's'}'
                        : 'Delivery fee added at checkout',
                    titleColor: const Color(0xFF075985),
                    subtitleColor: const Color(0xFF0369A1),
                  )
                else
                  const _ServiceRow(
                    icon: Icons.local_shipping_outlined,
                    iconBackground: Color(0xFFF1F5F9),
                    iconColor: Color(0xFF475569),
                    background: Colors.white,
                    border: Color(0xFFF1F5F9),
                    title: 'Delivery arranged with seller',
                    subtitle: 'Chat to agree on delivery details',
                    titleColor: Color(0xFF334155),
                    subtitleColor: Color(0xFF64748B),
                  ),
                if (product.shipsNationwide) ...[
                  const SizedBox(height: 8),
                  const _ServiceRow(
                    icon: Icons.location_on_outlined,
                    iconBackground: Color(0xFFE0E7FF),
                    iconColor: Color(0xFF4F46E5),
                    background: Color(0xFFEEF2FF),
                    border: Color(0xFFC7D2FE),
                    title: 'Ships nationwide across Ghana',
                    subtitle: "Available beyond the seller's local area",
                    titleColor: Color(0xFF312E81),
                    subtitleColor: Color(0xFF4338CA),
                  ),
                ],
                if (product.pickupAvailable) ...[
                  const SizedBox(height: 8),
                  _ServiceRow(
                    icon: Icons.storefront_outlined,
                    iconBackground: const Color(0xFFF97316),
                    iconColor: Colors.white,
                    background: const Color(0xFFFFF7ED),
                    border: const Color(0xFFFED7AA),
                    title: 'Pickup available from the seller shop',
                    subtitle: product.storeName != null && product.storeName!.trim().isNotEmpty
                        ? 'Collect in person at ${product.storeName}'
                        : 'Collect in person from the seller',
                    titleColor: const Color(0xFF7C2D12),
                    subtitleColor: const Color(0xFF9A3412),
                  ),
                ],
                if (product.cashOnDelivery) ...[
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'Cash on delivery available',
                      style: TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
                if (product.isNegotiable) ...[
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'Price is negotiable — chat the seller',
                      style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    IconData? icon,
    required String label,
    required Color background,
    required Color foreground,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.background,
    required this.border,
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final Color background;
  final Color border;
  final String title;
  final String subtitle;
  final Color titleColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: titleColor)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, height: 1.3, color: subtitleColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.product, required this.onMessage});
  final Product product;
  final VoidCallback onMessage;

  void _openStore(BuildContext context) {
    final slug = product.storeSlug?.trim();
    if (slug == null || slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller store is not available')),
      );
      return;
    }
    context.push('/stores/$slug');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openStore(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Builder(
                builder: (context) {
                  final photo = ApiConfig.resolveMediaUrl(product.sellerPhoto);
                  final hasPhoto = photo.isNotEmpty;
                  return CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.ringOrange,
                    backgroundImage: hasPhoto ? CachedNetworkImageProvider(photo) : null,
                    child: hasPhoto
                        ? null
                        : Text(
                            (product.storeName ?? 'S').substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
                          ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sold by ${product.storeName ?? 'Seller'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (product.sellerRating != null || product.sellerSales != null)
                      Text(
                        [
                          if (product.sellerRating != null) '★ ${product.sellerRating!.toStringAsFixed(1)}',
                          if (product.sellerSales != null) '${product.sellerSales} sales',
                        ].join(' · '),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tap to view store',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (product.sellerId != null)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(72, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: onMessage,
                  child: const Text('Chat'),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
