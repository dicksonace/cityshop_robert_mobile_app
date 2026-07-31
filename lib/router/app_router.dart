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
import '../screens/cart/direct_payment_screen.dart';
import '../screens/chat/messages_screens.dart';
import '../screens/product/product_detail_screen.dart';
import '../screens/shop/shop_shell.dart';
import '../screens/store/seller_store_screen.dart';
import '../store/app_store.dart';

bool _isDeepLinkPath(String path) {
  return path.startsWith('/products/') ||
      path.startsWith('/stores/') ||
      path.startsWith('/store/') ||
      path.startsWith('/orders/') ||
      path.startsWith('/messages/');
}

String _locationWithQuery(GoRouterState state) {
  final path = state.uri.path;
  if (!state.uri.hasQuery) return path;
  return '$path?${state.uri.query}';
}

GoRouter createRouter(AppStore store) {
  String? pendingAfterBoot;

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
      // Web uses /store/{slug}; app uses /stores/{slug}.
      GoRoute(
        path: '/store/:slug',
        redirect: (_, state) => '/stores/${state.pathParameters['slug']}',
      ),
      GoRoute(
        path: '/stores/:slug',
        builder: (_, state) => SellerStoreScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => OrderDetailScreen(
          orderId: int.parse(state.pathParameters['id']!),
          initialAction: state.uri.queryParameters['action'],
        ),
      ),
      GoRoute(
        path: '/orders/:id/direct-pay',
        builder: (_, state) => DirectPaymentScreen(
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
      final uri = state.uri;

      // cityshop://products/{slug} → /products/{slug}
      if (uri.scheme == 'cityshop' &&
          (uri.host == 'products' || uri.host == 'stores' || uri.host == 'store') &&
          uri.path.isNotEmpty) {
        final host = uri.host == 'store' ? 'stores' : uri.host;
        final target = '/$host${uri.path}';
        if (uri.hasQuery) return '$target?${uri.query}';
        return target;
      }

      final loc = state.matchedLocation;
      final path = uri.path;

      // Keep product/store deep links alive while splash boots.
      if (store.booting) {
        if (_isDeepLinkPath(path)) {
          pendingAfterBoot = _locationWithQuery(state);
        }
        return loc == '/splash' ? null : '/splash';
      }

      if (loc == '/splash') {
        final pending = pendingAfterBoot;
        pendingAfterBoot = null;
        return pending ?? '/shop';
      }

      return null;
    },
  );
}

extension AppStoreX on BuildContext {
  AppStore get store => read<AppStore>();
}
