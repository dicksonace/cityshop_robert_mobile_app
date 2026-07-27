import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../shop/shop_shell.dart';

class SellerStoreScreen extends StatefulWidget {
  const SellerStoreScreen({super.key, required this.slug});

  final String slug;

  @override
  State<SellerStoreScreen> createState() => _SellerStoreScreenState();
}

class _SellerStoreScreenState extends State<SellerStoreScreen> {
  bool loading = true;
  String? error;
  SellerStore? store;
  List<Product> products = [];
  final searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? search}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await context.read<AppStore>().fetchSellerStore(
            widget.slug,
            search: search,
          );
      if (!mounted) return;
      setState(() {
        store = result.store;
        products = result.products;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
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

  Future<void> _chatSeller() async {
    final s = store;
    if (s == null || s.sellerId == 0) return;
    final app = context.read<AppStore>();
    if (!app.isLoggedIn) {
      context.push('/login');
      return;
    }
    try {
      final opened = await app.openConversation(sellerId: s.sellerId);
      if (!mounted) return;
      context.push('/messages/${opened.conversation.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _callSeller() async {
    final phone = store?.mobile ?? store?.whatsapp;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone is not available')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = store;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: loading && s == null
          ? const FullPageLoader(label: 'Loading store…')
          : error != null && s == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: () => _load(), child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(search: searchCtrl.text.trim()),
                  child: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        expandedHeight: 168,
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        title: Text(s?.storeName ?? 'Store'),
                        flexibleSpace: FlexibleSpaceBar(
                          background: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                              ),
                            ),
                            child: SafeArea(
                              bottom: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    CircleAvatar(
                                      radius: 34,
                                      backgroundColor: Colors.white,
                                      backgroundImage: s?.shopPhoto != null
                                          ? CachedNetworkImageProvider(s!.shopPhoto!)
                                          : null,
                                      child: s?.shopPhoto == null
                                          ? Text(
                                              (s?.storeName ?? 'S').substring(0, 1).toUpperCase(),
                                              style: const TextStyle(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 28,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s?.storeName ?? 'Store',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 22,
                                              height: 1.15,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              if (s?.rating != null) '★ ${s!.rating!.toStringAsFixed(1)}',
                                              if (s?.totalSales != null) '${s!.totalSales} sales',
                                              '${s?.productCount ?? 0} products',
                                            ].join(' · '),
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.92),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (s?.location != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              s!.location!,
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.85),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _chatSeller,
                                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                      label: const Text('Chat seller'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _callSeller,
                                      icon: const Icon(Icons.phone_outlined, size: 18),
                                      label: const Text('Call'),
                                    ),
                                  ),
                                ],
                              ),
                              if ((s?.description ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  s!.description!.trim(),
                                  style: const TextStyle(height: 1.4, color: AppColors.textSecondary),
                                ),
                              ],
                              if ((s?.businessAddress ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.place_outlined, size: 16, color: AppColors.textMuted),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        s!.businessAddress!,
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),
                              TextField(
                                controller: searchCtrl,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: 'Search in this store',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.arrow_forward),
                                    onPressed: () => _load(search: searchCtrl.text.trim()),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                ),
                                onSubmitted: (q) => _load(search: q.trim()),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                products.isEmpty
                                    ? 'No products'
                                    : '${products.length} product${products.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (loading)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (products.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('No products found in this store')),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.68,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => ProductCard(product: products[index]),
                              childCount: products.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
