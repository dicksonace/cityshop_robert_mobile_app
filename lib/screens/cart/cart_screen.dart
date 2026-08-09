import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      await context.read<AppStore>().loadCart();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('My Cart')),
      body: !store.isLoggedIn
          ? const _NeedLogin(message: 'Login to view your cart')
          : loading
              ? const FullPageLoader(label: 'Loading cart…')
              : store.cartItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_cart_outlined, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          const Text('Your cart is empty', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => context.go('/shop'),
                            child: const Text('Continue shopping'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: store.cartItems.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = store.cartItems[index];
                              final image = item.product.primaryImageUrl;
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 72,
                                        height: 72,
                                        child: image != null
                                            ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover)
                                            : const ColoredBox(
                                                color: Color(0xFFF1F5F9),
                                                child: Icon(Icons.image),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.product.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _money.format(item.product.effectivePrice),
                                            style: const TextStyle(
                                              color: AppColors.accent,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              _QtyBtn(
                                                icon: Icons.remove,
                                                onTap: item.quantity <= 1
                                                    ? null
                                                    : () async {
                                                        try {
                                                          await store.updateCartItem(
                                                            item.id,
                                                            item.quantity - 1,
                                                          );
                                                        } on ApiException catch (e) {
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(content: Text(e.message)),
                                                            );
                                                          }
                                                        }
                                                      },
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                child: Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                              ),
                                              _QtyBtn(
                                                icon: Icons.add,
                                                onTap: () async {
                                                  try {
                                                    await store.updateCartItem(item.id, item.quantity + 1);
                                                  } on ApiException catch (e) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text(e.message)),
                                                      );
                                                    }
                                                  }
                                                },
                                              ),
                                              const Spacer(),
                                              IconButton(
                                                onPressed: () async {
                                                  await store.removeCartItem(item.id);
                                                },
                                                icon: const Icon(Icons.close, color: AppColors.danger),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        SafeArea(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(top: BorderSide(color: AppColors.border)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Text('Subtotal', style: TextStyle(fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Text(
                                      _money.format(store.cartSubtotal),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                PrimaryButton(
                                  label: 'Checkout',
                                  onPressed: () => context.push('/checkout'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
          color: onTap == null ? const Color(0xFFF8FAFC) : Colors.white,
        ),
        child: Icon(icon, size: 16, color: onTap == null ? AppColors.textMuted : AppColors.textPrimary),
      ),
    );
  }
}

class _NeedLogin extends StatelessWidget {
  const _NeedLogin({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => context.push('/login'), child: const Text('Login')),
        ],
      ),
    );
  }
}
