import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../screens/account/account_screens.dart';
import '../screens/account/manual_deposit_screen.dart';
import '../screens/account/notifications_screen.dart';
import '../screens/account/wallet_orders_screens.dart';
import '../screens/account/withdraw_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/cart/checkout_screen.dart';
import '../screens/cart/direct_pay_draft_screen.dart';
import '../screens/cart/direct_payment_screen.dart';
import '../screens/chat/messages_screens.dart';
import '../screens/product/product_detail_screen.dart';
import '../screens/shop/shop_shell.dart';
import '../screens/store/seller_store_screen.dart';
import '../store/app_store.dart';

/// Tab names accepted by `/shop?tab=`, matching the shell's IndexedStack order.
const _shellTabs = {
  'home': 0,
  'wallet': 1,
  'orders': 2,
  'messages': 3,
  'account': 4,
};

bool _isDeepLinkPath(String path) {
  return path.startsWith('/products/') ||
      path.startsWith('/product/') ||
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
      GoRoute(
        path: '/shop',
        builder: (_, state) => ShopShell(
          initialTab: _shellTabs[state.uri.queryParameters['tab']] ?? 0,
        ),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(path: '/wishlist', builder: (_, __) => const WishlistScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/wallet/manual-deposit', builder: (_, __) => const ManualDepositScreen()),
      GoRoute(path: '/wallet/withdraw', builder: (_, __) => const WithdrawScreen()),
      GoRoute(path: '/addresses', builder: (_, __) => const AddressesScreen()),
      GoRoute(path: '/profile/edit', builder: (_, __) => const ProfileEditScreen()),
      GoRoute(path: '/profile/password', builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
        path: '/products/:slug',
        builder: (_, state) => ProductDetailScreen(slug: state.pathParameters['slug']!),
      ),
      // Older links point at a single product by id; the API answers to both.
      GoRoute(
        path: '/product/:slug',
        redirect: (_, state) => '/products/${state.pathParameters['slug']}',
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
        path: '/checkout/direct-pay',
        builder: (_, state) {
          final extra = state.extra;
          List<Map<String, dynamic>>? packages;
          Map<String, dynamic>? shipping;
          if (extra is Map) {
            final rawPackages = extra['packages'];
            if (rawPackages is List) {
              packages = rawPackages
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
            final rawShipping = extra['shipping'];
            if (rawShipping is Map) {
              shipping = Map<String, dynamic>.from(rawShipping);
            }
          }
          return DirectPayDraftScreen(
            initialPackages: packages,
            initialShipping: shipping,
          );
        },
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
      const deepLinkHosts = {'products', 'product', 'stores', 'store'};
      if (uri.scheme == 'cityshop' && deepLinkHosts.contains(uri.host) && uri.path.isNotEmpty) {
        final host = switch (uri.host) {
          'store' => 'stores',
          'product' => 'products',
          _ => uri.host,
        };
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
