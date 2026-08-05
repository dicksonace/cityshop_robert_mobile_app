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

  /// Whether this buyer's like was already counted in the fetched total, so the
  /// displayed count can follow the heart without refetching the product.
  bool likeCounted = false;

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
      final store = context.read<AppStore>();
      final detail = await store.fetchProductDetail(widget.slug);
      if (!mounted) return;
      unawaited(store.recordProductView(detail.product));
      setState(() {
        product = detail.product;
        related = detail.related;
        reviews = detail.reviews;
        likeCounted = store.wishlistProductIds.contains(detail.product.id);
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
            tooltip: 'Share',
            onPressed: _shareProduct,
            icon: const Icon(Icons.share_outlined),
          ),
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
                  qty: qty,
                  likeCount: p.wishlistAdds + (wishlisted ? 1 : 0) - (likeCounted ? 1 : 0),
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
    required this.qty,
    required this.likeCount,
    required this.onQtyChanged,
    required this.onMessage,
  });

  final Product product;
  final List<Product> related;
  final List<Map<String, dynamic>> reviews;
  final int qty;
  final int likeCount;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onMessage;

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
                  Text('$likeCount', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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
  bool _muted = true;

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
