import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/product_image_limits.dart';
import '../../widgets/product_video_field.dart';
import '../../widgets/product_video_limits.dart';
import '../../widgets/tab_refresh.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

String _categoryEmoji(Map<String, dynamic> category) {
  final stored = '${category['icon'] ?? ''}'.trim();
  if (stored.isNotEmpty && !stored.contains('/') && stored.length <= 4) {
    return stored;
  }
  final key = '${category['slug'] ?? ''} ${category['name'] ?? ''}'.toLowerCase();
  if (key.contains('phone') || key.contains('tablet')) return '📱';
  if (key.contains('computer') || key.contains('laptop')) return '💻';
  if (key.contains('electronic')) return '⚡';
  if (key.contains('appliance')) return '🔌';
  if (key.contains('fashion') || key.contains('cloth')) return '👗';
  if (key.contains('bag') || key.contains('shoe')) return '👜';
  if (key.contains('beauty')) return '💄';
  if (key.contains('home') || key.contains('garden')) return '🏠';
  if (key.contains('food') || key.contains('beverage')) return '🍔';
  if (key.contains('groc')) return '🛒';
  if (key.contains('health') || key.contains('pharm')) return '💊';
  if (key.contains('baby') || key.contains('kid')) return '🍼';
  if (key.contains('sport')) return '⚽';
  if (key.contains('toy') || key.contains('game')) return '🎮';
  if (key.contains('book') || key.contains('educat')) return '📚';
  if (key.contains('office') || key.contains('station')) return '📎';
  if (key.contains('jewel') || key.contains('watch')) return '💍';
  if (key.contains('vehicle') || key.contains('car')) return '🚗';
  if (key.contains('auto') || key.contains('part')) return '🔧';
  if (key.contains('tool') || key.contains('hardware')) return '🛠️';
  if (key.contains('pet')) return '🐾';
  return '📦';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _asMaps(dynamic value) {
  if (value is! List) return [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

class SellerProductsTab extends StatefulWidget {
  const SellerProductsTab({super.key});

  @override
  State<SellerProductsTab> createState() => _SellerProductsTabState();
}

class _SellerProductsTabState extends State<SellerProductsTab> with AutoRefreshTab {
  String status = 'all';
  final search = TextEditingController();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> products = [];
  Map<String, dynamic> counts = {};
  bool canCreate = true;
  int page = 1;
  int lastPage = 1;
  bool loadingMore = false;
  bool selecting = false;
  final selected = <int>{};

  static const filters = [
    ('all', 'All'),
    ('approved', 'Live'),
    ('draft', 'Hidden'),
    ('sold_out', 'Sold out'),
  ];

  @override
  int? get tabIndex => 2;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshTabData({required bool background}) => _load(background: background);

  Future<void> _load({bool background = false}) async {
    if (!background) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await context.read<AppStore>().loadSellerProducts(
            status: status == 'all' ? null : status,
            search: search.text,
            page: 1,
          );
      if (!mounted) return;
      setState(() {
        products = _asMaps(data['data']);
        counts = _asMap(data['counts']);
        canCreate = data['can_create'] != false;
        final meta = _asMap(data['meta']);
        page = (meta['current_page'] as num?)?.toInt() ?? 1;
        lastPage = (meta['last_page'] as num?)?.toInt() ?? 1;
        selected.removeWhere((id) => products.every((p) => (p['id'] as num?)?.toInt() != id));
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (!background || products.isEmpty) error = e.message;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!background || products.isEmpty) error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || page >= lastPage) return;
    setState(() => loadingMore = true);
    try {
      final data = await context.read<AppStore>().loadSellerProducts(
            status: status == 'all' ? null : status,
            search: search.text,
            page: page + 1,
          );
      if (!mounted) return;
      setState(() {
        products = [...products, ..._asMaps(data['data'])];
        final meta = _asMap(data['meta']);
        page = (meta['current_page'] as num?)?.toInt() ?? page + 1;
        lastPage = (meta['last_page'] as num?)?.toInt() ?? lastPage;
        loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> _duplicate(int id) async {
    try {
      final res = await context.read<AppStore>().duplicateSellerProduct(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] as String? ?? 'Product duplicated.')),
      );
      await _load(background: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggle(int id) async {
    try {
      final res = await context.read<AppStore>().toggleSellerProductVisibility(id);
      if (!mounted) return;
      final message = res['message'] as String?;
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      await _load(background: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _bulk(String action) async {
    if (selected.isEmpty) return;
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete selected products?'),
          content: Text('${selected.length} product(s) will be removed from your store.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final res = await context.read<AppStore>().bulkSellerProducts(
            action: action,
            productIds: selected.toList(),
          );
      if (!mounted) return;
      setState(() {
        selecting = false;
        selected.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] as String? ?? 'Updated.')),
      );
      await _load(background: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('$name will be removed from your store.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final store = context.read<AppStore>();
    try {
      await store.deleteSellerProduct(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product deleted.')));
      await _load(background: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(selecting ? '${selected.length} selected' : 'Products'),
        leading: selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  selecting = false;
                  selected.clear();
                }),
              )
            : null,
        actions: [
          if (selecting) ...[
            IconButton(
              tooltip: 'Hide',
              onPressed: selected.isEmpty ? null : () => _bulk('hide'),
              icon: const Icon(Icons.visibility_off_outlined),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: selected.isEmpty ? null : () => _bulk('delete'),
              icon: const Icon(Icons.delete_outline),
            ),
          ] else
            TextButton(
              onPressed: products.isEmpty
                  ? null
                  : () => setState(() => selecting = true),
              child: const Text('Select'),
            ),
        ],
      ),
      floatingActionButton: selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                if (!canCreate) {
                  context.push('/seller/activation');
                  return;
                }
                final created = await context.push<bool>('/seller/products/new');
                if (created == true && mounted) _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: search,
              decoration: InputDecoration(
                hintText: 'Search products',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    search.clear();
                    _load();
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                for (final filter in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        filter.$1 == 'all'
                            ? '${filter.$2} ${(counts['all'] as num?)?.toInt() ?? ''}'.trim()
                            : '${filter.$2} ${(counts[filter.$1] as num?)?.toInt() ?? ''}'.trim(),
                      ),
                      selected: status == filter.$1,
                      onSelected: (_) {
                        setState(() => status = filter.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (!canCreate)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Material(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  title: const Text('Pay the annual seller fee to publish products.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/seller/activation'),
                ),
              ),
            ),
          Expanded(
            child: loading && products.isEmpty
                ? const FullPageLoader(label: 'Loading products…')
                : error != null && products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!, textAlign: TextAlign.center),
                            FilledButton(onPressed: refreshNow, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: refreshNow,
                        child: products.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.textMuted),
                                  SizedBox(height: 12),
                                  Text('No products yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                                ],
                              )
                            : NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 240) {
                                    _loadMore();
                                  }
                                  return false;
                                },
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                                  itemCount: products.length + (loadingMore ? 1 : 0),
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, i) {
                                    if (i >= products.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }
                                    final product = products[i];
                                    final id = (product['id'] as num?)?.toInt() ?? 0;
                                    final live = product['is_live'] == true;
                                    final checked = selected.contains(id);
                                    return Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      child: ListTile(
                                        onTap: () async {
                                          if (selecting) {
                                            setState(() {
                                              if (checked) {
                                                selected.remove(id);
                                              } else {
                                                selected.add(id);
                                              }
                                            });
                                            return;
                                          }
                                          final changed = await context.push<bool>('/seller/products/$id/edit');
                                          if (changed == true && mounted) _load();
                                        },
                                        onLongPress: () => setState(() {
                                          selecting = true;
                                          selected.add(id);
                                        }),
                                        leading: selecting
                                            ? Checkbox(
                                                value: checked,
                                                onChanged: (v) => setState(() {
                                                  if (v == true) {
                                                    selected.add(id);
                                                  } else {
                                                    selected.remove(id);
                                                  }
                                                }),
                                              )
                                            : _Thumb(url: product['image'] as String?),
                                        title: Text(
                                          product['name'] as String? ?? 'Product',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                        subtitle: Text(
                                          [
                                            live ? 'Live' : (product['status'] as String? ?? 'hidden'),
                                            'Qty ${(product['quantity'] as num?)?.toInt() ?? 0}',
                                            _money.format((product['discount_price'] as num?)?.toDouble() ?? (product['price'] as num?)?.toDouble() ?? 0),
                                          ].join(' · '),
                                        ),
                                        trailing: selecting
                                            ? null
                                            : PopupMenuButton<String>(
                                                onSelected: (value) {
                                                  if (value == 'toggle') _toggle(id);
                                                  if (value == 'duplicate') _duplicate(id);
                                                  if (value == 'analytics') context.push('/seller/products/$id/analytics');
                                                  if (value == 'delete') _delete(id, product['name'] as String? ?? 'Product');
                                                },
                                                itemBuilder: (_) => [
                                                  PopupMenuItem(value: 'toggle', child: Text(live ? 'Hide from store' : 'Make live')),
                                                  const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                                                  const PopupMenuItem(value: 'analytics', child: Text('Analytics')),
                                                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                                ],
                                              ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class SellerProductFormScreen extends StatefulWidget {
  const SellerProductFormScreen({super.key, this.productId});

  final int? productId;

  @override
  State<SellerProductFormScreen> createState() => _SellerProductFormScreenState();
}

class _SellerProductFormScreenState extends State<SellerProductFormScreen> {
  final name = TextEditingController();
  final price = TextEditingController();
  final discount = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final description = TextEditingController();
  final sku = TextEditingController();
  final brand = TextEditingController();
  final wholesale = TextEditingController();
  final minQty = TextEditingController();
  final deliveryFee = TextEditingController();
  final deliveryDays = TextEditingController();
  final weight = TextEditingController();
  final lowStock = TextEditingController();
  final images = <XFile>[];
  final existingImages = <Map<String, dynamic>>[];
  final removeImageIds = <int>{};
  final specs = <String, String>{};
  XFile? video;
  int? videoDuration;
  int? videoBytes;
  String? existingVideoUrl;
  int? existingVideoDuration;
  bool removeExistingVideo = false;
  bool checkingVideo = false;
  String? videoError;
  List<Map<String, dynamic>> categories = [];
  int? categoryId;
  String shippingType = 'buyer';
  String condition = 'new';
  bool negotiable = false;
  bool cashOnDelivery = false;
  bool pickup = false;
  bool nationwide = true;
  bool inGhana = true;
  bool loading = false;
  bool saving = false;
  String? error;

  bool get isEdit => widget.productId != null;

  Map<String, dynamic>? get selectedCategory {
    for (final c in categories) {
      if ((c['id'] as num?)?.toInt() == categoryId) return c;
    }
    return null;
  }

  List<Map<String, dynamic>> get specFields => _asMaps(selectedCategory?['spec_fields']);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    discount.dispose();
    quantity.dispose();
    description.dispose();
    sku.dispose();
    brand.dispose();
    wholesale.dispose();
    minQty.dispose();
    deliveryFee.dispose();
    deliveryDays.dispose();
    weight.dispose();
    lowStock.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => loading = true);
    try {
      final store = context.read<AppStore>();
      final list = await store.loadSellerProducts(perPage: 1);
      categories = _asMaps(list['categories']);
      if (isEdit) {
        final product = await store.loadSellerProduct(widget.productId!);
        name.text = product['name'] as String? ?? '';
        price.text = '${(product['price'] as num?) ?? ''}';
        discount.text = product['discount_price'] == null ? '' : '${product['discount_price']}';
        quantity.text = '${(product['quantity'] as num?)?.toInt() ?? 1}';
        description.text = product['description'] as String? ?? '';
        sku.text = product['sku'] as String? ?? '';
        brand.text = product['brand'] as String? ?? '';
        wholesale.text = product['wholesale_price'] == null ? '' : '${product['wholesale_price']}';
        minQty.text = product['minimum_order_quantity'] == null ? '' : '${product['minimum_order_quantity']}';
        deliveryFee.text = product['delivery_fee'] == null ? '' : '${product['delivery_fee']}';
        deliveryDays.text = product['delivery_days'] == null ? '' : '${product['delivery_days']}';
        weight.text = product['weight'] == null ? '' : '${product['weight']}';
        lowStock.text = product['low_stock_alert'] == null ? '' : '${product['low_stock_alert']}';
        categoryId = (product['category_id'] as num?)?.toInt();
        shippingType = product['shipping_type'] as String? ?? 'buyer';
        final savedCondition = product['condition'] as String?;
        condition = const {'new', 'used', 'refurbished'}.contains(savedCondition)
            ? savedCondition!
            : 'new';
        negotiable = product['is_negotiable'] == true;
        cashOnDelivery = product['cash_on_delivery'] == true;
        pickup = product['pickup_available'] == true;
        nationwide = product['ships_nationwide'] != false;
        inGhana = product['in_ghana'] != false;
        existingImages
          ..clear()
          ..addAll(_asMaps(product['images']));
        existingVideoUrl = ApiConfig.resolveMediaUrl(product['video_url'] as String?);
        if (existingVideoUrl != null && existingVideoUrl!.isEmpty) existingVideoUrl = null;
        existingVideoDuration = (product['video_duration'] as num?)?.toInt();
        removeExistingVideo = false;
        video = null;
        videoDuration = null;
        videoBytes = null;
        videoError = null;
        final existingSpecs = _asMap(product['specifications']);
        specs
          ..clear()
          ..addAll({for (final e in existingSpecs.entries) e.key: '${e.value}'});
      }
      if (mounted) setState(() => loading = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          loading = false;
        });
      }
    }
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: ProductVideoLimits.maxSeconds),
    );
    if (picked == null) return;
    setState(() {
      checkingVideo = true;
      videoError = null;
    });
    VideoPlayerController? probe;
    try {
      // Prefer XFile.length() — more reliable than File() on some Android content paths.
      var bytes = 0;
      try {
        bytes = await picked.length();
      } catch (_) {
        bytes = 0;
      }
      if (bytes <= 0) {
        try {
          bytes = await File(picked.path).length();
        } catch (_) {
          bytes = 0;
        }
      }
      final sizeErr = ProductVideoLimits.sizeError(bytes);
      if (sizeErr != null) {
        if (!mounted) return;
        setState(() {
          checkingVideo = false;
          videoError = sizeErr;
        });
        return;
      }

      probe = VideoPlayerController.file(File(picked.path));
      await probe.initialize();
      final seconds = probe.value.duration.inMilliseconds / 1000;
      await probe.dispose();
      probe = null;

      final durationErr = ProductVideoLimits.durationError(seconds);
      if (durationErr != null) {
        if (!mounted) return;
        setState(() {
          checkingVideo = false;
          videoError = durationErr;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        video = picked;
        videoBytes = bytes;
        videoDuration = seconds.isFinite && seconds > 0
            ? seconds.round().clamp(1, ProductVideoLimits.maxSeconds)
            : null;
        removeExistingVideo = false;
        checkingVideo = false;
        videoError = null;
      });
    } catch (_) {
      await probe?.dispose();
      if (!mounted) return;
      setState(() {
        checkingVideo = false;
        videoError =
            'Could not read this video. Use MP4, WebM, MOV, or 3GP under 1 minute and 50 MB.';
      });
    }
  }

  void _removeVideo() {
    setState(() {
      if (video != null) {
        video = null;
        videoDuration = null;
        videoBytes = null;
      } else {
        removeExistingVideo = true;
      }
      videoError = null;
    });
  }

  Future<void> _pickImages() async {
    final keptExisting = existingImages.length - removeImageIds.length;
    final remaining = ProductImageLimits.maxImages - keptExisting - images.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum ${ProductImageLimits.maxImages} photos.')),
      );
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 82, limit: remaining);
    if (picked.isEmpty) return;
    setState(() => images.addAll(picked.take(remaining)));
  }

  Map<String, dynamic> _listing() {
    return {
      'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
      'brand': brand.text.trim().isEmpty ? null : brand.text.trim(),
      'condition': condition,
      'wholesale_price': double.tryParse(wholesale.text.trim()),
      'minimum_order_quantity': int.tryParse(minQty.text.trim()),
      'is_negotiable': negotiable,
      'low_stock_alert': int.tryParse(lowStock.text.trim()),
      'weight': double.tryParse(weight.text.trim()),
      'shipping_type': shippingType,
      if (shippingType == 'paid') 'delivery_fee': double.tryParse(deliveryFee.text.trim()),
      'delivery_days': int.tryParse(deliveryDays.text.trim()),
      'cash_on_delivery': cashOnDelivery,
      'pickup_available': pickup,
      'ships_nationwide': nationwide,
      'in_ghana': inGhana,
      'specifications': {
        for (final f in specFields)
          if ((f['key'] as String?)?.isNotEmpty == true) (f['key'] as String): specs[f['key'] as String] ?? '',
      }..removeWhere((k, v) => v.trim().isEmpty),
    };
  }

  Future<void> _save() async {
    final parsedPrice = double.tryParse(price.text.trim());
    final parsedQty = int.tryParse(quantity.text.trim());
    if (name.text.trim().isEmpty || parsedPrice == null || parsedQty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a name, price, and quantity.')),
      );
      return;
    }
    if (shippingType == 'paid' && (double.tryParse(deliveryFee.text.trim()) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a delivery fee for paid shipping.')),
      );
      return;
    }
    if (!isEdit && images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product photo.')),
      );
      return;
    }
    if (video != null) {
      final bytes = videoBytes ?? 0;
      final sizeErr = ProductVideoLimits.sizeError(bytes > 0 ? bytes : -1);
      if (bytes <= 0 || sizeErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sizeErr ?? 'Video file size could not be verified. Pick the clip again.')),
        );
        return;
      }
    }
    setState(() => saving = true);
    try {
      final store = context.read<AppStore>();
      final listing = _listing();
      if (isEdit) {
        await store.updateSellerProduct(
          widget.productId!,
          name: name.text.trim(),
          description: description.text.trim(),
          price: parsedPrice,
          discountPrice: double.tryParse(discount.text.trim()),
          quantity: parsedQty,
          categoryId: categoryId,
          listing: listing,
          removeImageIds: removeImageIds.toList(),
        );
        if (images.isNotEmpty) {
          await store.uploadSellerProductImages(widget.productId!, images.map((e) => e.path).toList());
        }
        if (video != null) {
          await store.uploadSellerProductVideo(
            widget.productId!,
            filePath: video!.path,
            duration: videoDuration,
            filename: video!.name.trim().isEmpty ? 'product.mp4' : video!.name,
          );
        } else if (removeExistingVideo) {
          await store.removeSellerProductVideo(widget.productId!);
        }
      } else {
        await store.createSellerProduct(
          name: name.text.trim(),
          price: parsedPrice,
          quantity: parsedQty,
          description: description.text.trim(),
          categoryId: categoryId,
          discountPrice: double.tryParse(discount.text.trim()),
          imagePaths: images.map((e) => e.path).toList(),
          videoPath: video?.path,
          videoDuration: videoDuration,
          listing: listing,
        );
      }
      if (!mounted) return;
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      final msg = e.message.trim().isEmpty || e.message == 'Server Error'
          ? (video != null
              ? 'Could not save this video. Try another MP4 under 1 minute, or compress it first.'
              : 'Something went wrong. Please try again.')
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/seller');
            }
          },
        ),
        title: Text(isEdit ? 'Edit product' : 'Add product'),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading…')
          : error != null
              ? Center(child: Text(error!))
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Product name')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Price (GHS)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: discount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Discount price (optional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final id = await Navigator.of(context).push<int?>(
                          MaterialPageRoute(
                            builder: (_) => _CategoryPickerScreen(
                              categories: categories,
                              selectedId: categoryId,
                            ),
                          ),
                        );
                        if (id == null || !mounted) return;
                        setState(() => categoryId = id == 0 ? null : id);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          suffixIcon: Icon(Icons.chevron_right),
                        ),
                        child: Row(
                          children: [
                            if (selectedCategory != null) ...[
                              Text(_categoryEmoji(selectedCategory!), style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                selectedCategory?['name'] as String? ?? 'Select category',
                                style: TextStyle(
                                  color: selectedCategory == null ? AppColors.textMuted : AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      initiallyExpanded: true,
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Photos & video', style: TextStyle(fontWeight: FontWeight.w800)),
                      children: [
                        if (existingImages.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 84,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: existingImages.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final img = existingImages[i];
                                final id = (img['id'] as num?)?.toInt() ?? 0;
                                final gone = removeImageIds.contains(id);
                                return Stack(
                                  children: [
                                    Opacity(
                                      opacity: gone ? 0.35 : 1,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: CachedNetworkImage(
                                          imageUrl: img['url'] as String? ?? '',
                                          width: 84,
                                          height: 84,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: IconButton(
                                        icon: Icon(gone ? Icons.undo : Icons.close, size: 18),
                                        onPressed: () => setState(() {
                                          if (gone) {
                                            removeImageIds.remove(id);
                                          } else {
                                            removeImageIds.add(id);
                                          }
                                        }),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final kept = existingImages.length - removeImageIds.length;
                            final total = kept + images.length;
                            final canAdd = total < ProductImageLimits.maxImages;
                            return OutlinedButton.icon(
                              onPressed: canAdd ? _pickImages : null,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(
                                images.isEmpty && kept == 0
                                    ? 'Add photos (up to ${ProductImageLimits.maxImages})'
                                    : canAdd
                                        ? 'Add more photos ($total/${ProductImageLimits.maxImages})'
                                        : 'Photos full ($total/${ProductImageLimits.maxImages})',
                              ),
                            );
                          },
                        ),
                        if (images.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 84,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: images.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) => ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(File(images[i].path), width: 84, height: 84, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        ProductVideoField(
                          networkUrl: removeExistingVideo ? null : existingVideoUrl,
                          filePath: video?.path,
                          durationSeconds: video != null ? videoDuration : existingVideoDuration,
                          fileSizeBytes: video != null ? videoBytes : null,
                          checking: checkingVideo,
                          error: videoError,
                          onPick: _pickVideo,
                          onRemove: _removeVideo,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Details', style: TextStyle(fontWeight: FontWeight.w800)),
                      children: [
                        TextField(controller: sku, decoration: const InputDecoration(labelText: 'SKU')),
                        const SizedBox(height: 12),
                        TextField(controller: brand, decoration: const InputDecoration(labelText: 'Brand')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: condition,
                          decoration: const InputDecoration(labelText: 'Condition'),
                          items: const [
                            DropdownMenuItem(value: 'new', child: Text('New')),
                            DropdownMenuItem(value: 'used', child: Text('Used')),
                            DropdownMenuItem(value: 'refurbished', child: Text('Refurbished')),
                          ],
                          onChanged: (v) => setState(() => condition = v ?? 'new'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: weight,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Weight (kg)'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: lowStock,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Low stock alert'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Price is negotiable'),
                          value: negotiable,
                          onChanged: (v) => setState(() => negotiable = v),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Wholesale', style: TextStyle(fontWeight: FontWeight.w800)),
                      children: [
                        TextField(
                          controller: wholesale,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Wholesale price (GHS)'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: minQty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Minimum order quantity'),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Shipping', style: TextStyle(fontWeight: FontWeight.w800)),
                      children: [
                        DropdownButtonFormField<String>(
                          value: shippingType,
                          decoration: const InputDecoration(labelText: 'Shipping'),
                          items: const [
                            DropdownMenuItem(value: 'free', child: Text('Free shipping')),
                            DropdownMenuItem(value: 'paid', child: Text('Seller sets a delivery fee')),
                            DropdownMenuItem(value: 'buyer', child: Text('Buyer pays delivery')),
                          ],
                          onChanged: (v) => setState(() => shippingType = v ?? 'buyer'),
                        ),
                        if (shippingType == 'paid') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: deliveryFee,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Delivery fee (GHS)'),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: deliveryDays,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Delivery days'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Cash on delivery'),
                          value: cashOnDelivery,
                          onChanged: (v) => setState(() => cashOnDelivery = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Pickup available'),
                          value: pickup,
                          onChanged: (v) => setState(() => pickup = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Ships nationwide'),
                          value: nationwide,
                          onChanged: (v) => setState(() => nationwide = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('In Ghana'),
                          value: inGhana,
                          onChanged: (v) => setState(() => inGhana = v),
                        ),
                      ],
                    ),
                    if (specFields.isNotEmpty)
                      ExpansionTile(
                        initiallyExpanded: true,
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Specifications', style: TextStyle(fontWeight: FontWeight.w800)),
                        children: [
                          for (final field in specFields) ...[
                            const SizedBox(height: 12),
                            if ((field['type'] as String?) == 'select')
                              DropdownButtonFormField<String?>(
                                value: (field['options'] as List?)?.contains(specs[field['key']]) == true
                                    ? specs[field['key'] as String]
                                    : null,
                                decoration: InputDecoration(labelText: field['label'] as String? ?? 'Spec'),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Not set')),
                                  for (final opt in (field['options'] as List? ?? []))
                                    DropdownMenuItem(value: '$opt', child: Text('$opt')),
                                ],
                                onChanged: (v) => setState(() {
                                  final key = field['key'] as String? ?? '';
                                  if (v == null) {
                                    specs.remove(key);
                                  } else {
                                    specs[key] = v;
                                  }
                                }),
                              )
                            else
                              TextFormField(
                                initialValue: specs[field['key'] as String? ?? ''] ?? '',
                                decoration: InputDecoration(labelText: field['label'] as String? ?? 'Spec'),
                                onChanged: (v) => specs[field['key'] as String? ?? ''] = v,
                              ),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: saving ? null : _save,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(saving ? 'Saving…' : (isEdit ? 'Save changes' : 'Publish product')),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CategoryPickerScreen extends StatelessWidget {
  const _CategoryPickerScreen({
    required this.categories,
    this.selectedId,
  });

  final List<Map<String, dynamic>> categories;
  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    final rows = <({int? id, String name, String emoji})>[
      (id: null, name: 'No category', emoji: '🏷️'),
      for (final category in categories)
        (
          id: (category['id'] as num?)?.toInt(),
          name: category['name'] as String? ?? 'Category',
          emoji: _categoryEmoji(category),
        ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Select category', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6), indent: 56),
        itemBuilder: (context, index) {
          final row = rows[index];
          final selected = row.id == selectedId;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Text(row.emoji, style: const TextStyle(fontSize: 22)),
            title: Text(
              row.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.accent : const Color(0xFFD1D5DB),
            ),
            onTap: () => Navigator.pop(context, row.id ?? 0),
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const CircleAvatar(
        backgroundColor: Color(0xFFFFEDD5),
        child: Icon(Icons.inventory_2_outlined, color: AppColors.accent),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(imageUrl: url!, width: 48, height: 48, fit: BoxFit.cover),
    );
  }
}
