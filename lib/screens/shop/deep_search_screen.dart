import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart';

/// Alibaba-style results: mode tabs, then a Deep Search results row.
class DeepSearchScreen extends StatefulWidget {
  const DeepSearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<DeepSearchScreen> createState() => _DeepSearchScreenState();
}

class _DeepSearchScreenState extends State<DeepSearchScreen> {
  late final TextEditingController _query;
  Timer? _debounce;
  int _gen = 0;
  String _mode = 'all';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<Product> _products = const [];
  List<_StoreHit> _stores = const [];

  static const _modes = <(String, String)>[
    ('all', 'All'),
    ('products', 'Products'),
    ('stores', 'Stores'),
    ('ghana', 'In Ghana'),
  ];

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) {
      _run();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onTyped(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    final q = _query.text.trim();
    final gen = ++_gen;
    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _searched = false;
        _error = null;
        _products = const [];
        _stores = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
    });

    try {
      final result = await context.read<AppStore>().deepSearch(query: q, mode: _mode);
      if (!mounted || gen != _gen) return;
      setState(() {
        _products = result.products;
        _stores = result.stores
            .map(_StoreHit.fromJson)
            .where((store) => store.slug.isNotEmpty)
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = 'Deep search failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showProducts = _mode != 'stores';
    final showStores = _mode == 'all' || _mode == 'stores';
    final empty = _searched && !_loading && _error == null && _products.isEmpty && _stores.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: TextField(
                        controller: _query,
                        autofocus: widget.initialQuery.trim().isEmpty,
                        textInputAction: TextInputAction.search,
                        onChanged: _onTyped,
                        onSubmitted: (_) {
                          _debounce?.cancel();
                          _run();
                        },
                        decoration: const InputDecoration(
                          hintText: 'Deep search products, stores…',
                          prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _modes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (context, index) {
                  final mode = _modes[index];
                  final selected = _mode == mode.$1;
                  return InkWell(
                    onTap: () {
                      if (_mode == mode.$1) return;
                      setState(() => _mode = mode.$1);
                      _debounce?.cancel();
                      _run();
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          mode.$2,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 2,
                          width: 28,
                          color: selected ? AppColors.accent : Colors.transparent,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            if (_searched)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      _loading ? Icons.travel_explore_rounded : Icons.check_circle_rounded,
                      size: 18,
                      color: _loading ? AppColors.accent : AppColors.emerald,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Deep Search results',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center),
                          ),
                        )
                      : !_searched
                          ? const Center(
                              child: Text(
                                'Search products and stores',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : empty
                              ? Center(
                                  child: Text(
                                    'No matches for “${_query.text.trim()}”',
                                    style: const TextStyle(color: AppColors.textSecondary),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  children: [
                                    if (showStores && _stores.isNotEmpty) ...[
                                      const Text(
                                        'Stores',
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._stores.map((store) => _StoreRow(store: store)),
                                      const SizedBox(height: 16),
                                    ],
                                    if (showProducts && _products.isNotEmpty) ...[
                                      Text(
                                        _mode == 'ghana' ? 'In Ghana' : 'Products',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          mainAxisSpacing: 12,
                                          crossAxisSpacing: 12,
                                          childAspectRatio: 0.66,
                                        ),
                                        itemCount: _products.length,
                                        itemBuilder: (context, index) => ProductCard(product: _products[index]),
                                      ),
                                    ],
                                  ],
                                ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreHit {
  const _StoreHit({
    required this.name,
    required this.slug,
    required this.productsCount,
    this.photo,
  });

  final String name;
  final String slug;
  final String? photo;
  final int productsCount;

  factory _StoreHit.fromJson(Map<String, dynamic> json) {
    return _StoreHit(
      name: json['name'] as String? ?? 'Store',
      slug: json['slug'] as String? ?? '',
      photo: json['shop_photo'] as String?,
      productsCount: (json['products_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class _StoreRow extends StatelessWidget {
  const _StoreRow({required this.store});

  final _StoreHit store;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFFFEDD5),
        backgroundImage: store.photo != null && store.photo!.isNotEmpty
            ? CachedNetworkImageProvider(store.photo!)
            : null,
        child: store.photo == null || store.photo!.isEmpty
            ? const Icon(Icons.storefront_outlined, color: AppColors.accent)
            : null,
      ),
      title: Text(store.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        store.productsCount == 1 ? '1 product' : '${store.productsCount} products',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push('/stores/${store.slug}'),
    );
  }
}
