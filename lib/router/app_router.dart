import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../screens/account/account_screens.dart';
import '../screens/account/wallet_orders_screens.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/cart/checkout_screen.dart';
import '../screens/chat/messages_screens.dart';
import '../screens/product/product_detail_screen.dart';
import '../screens/shop/shop_shell.dart';
import '../screens/store/seller_store_screen.dart';
import '../store/app_store.dart';

GoRouter createRouter(AppStore store) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: store,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/shop', builder: (_, __) => const ShopShell()),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(path: '/wishlist', builder: (_, __) => const WishlistScreen()),
      GoRoute(path: '/addresses', builder: (_, __) => const AddressesScreen()),
      GoRoute(path: '/profile/edit', builder: (_, __) => const ProfileEditScreen()),
      GoRoute(path: '/profile/password', builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
        path: '/products/:slug',
        builder: (_, state) => ProductDetailScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/stores/:slug',
        builder: (_, state) => SellerStoreScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => OrderDetailScreen(
          orderId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/messages/:id',
        builder: (_, state) => ChatScreen(
          conversationId: int.parse(state.pathParameters['id']!),
        ),
      ),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (store.booting) {
        return loc == '/splash' ? null : '/splash';
      }
      if (loc == '/splash') return '/shop';
      return null;
    },
  );
}

extension AppStoreX on BuildContext {
  AppStore get store => read<AppStore>();
}
