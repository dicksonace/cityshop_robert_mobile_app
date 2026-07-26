import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(product?.name ?? 'Product'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
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
              : _Body(product: product!),
      bottomNavigationBar: product == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ElevatedButton(
                  onPressed: () {
                    final loggedIn = context.read<AppStore>().isLoggedIn;
                    if (!loggedIn) {
                      context.push('/login');
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add to cart coming next')),
                    );
                  },
                  child: Text(
                    context.watch<AppStore>().isLoggedIn ? 'Add to cart' : 'Login to buy',
                  ),
                ),
              ),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final image = product.primaryImageUrl;

    return ListView(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: image != null
              ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover)
              : Container(color: AppColors.border, child: const Icon(Icons.image, size: 64)),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                product.name,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
              ),
              const SizedBox(height: 8),
              Text(
                _money.format(product.effectivePrice),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              if (product.storeName != null) ...[
                const SizedBox(height: 8),
                Text('Sold by ${product.storeName}', style: const TextStyle(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (product.inGhana)
                    Chip(
                      label: const Text('In Ghana'),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      side: BorderSide.none,
                    ),
                  if (product.freeShipping)
                    Chip(
                      label: const Text('Free delivery'),
                      backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                      side: BorderSide.none,
                    ),
                  if (product.rating > 0)
                    Chip(
                      avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                      label: Text('${product.rating.toStringAsFixed(1)} (${product.reviewCount})'),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 16),
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
