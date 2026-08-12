import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../screens/account/account_screens.dart';
import '../screens/account/manual_deposit_screen.dart';
import '../screens/account/manual_deposit_status_screen.dart';
import '../screens/account/notifications_screen.dart';
import '../screens/account/payment_pin_screen.dart';
import '../screens/account/wallet_orders_screens.dart';
import '../screens/account/withdraw_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/cart/checkout_screen.dart';
import '../screens/cart/direct_pay_draft_screen.dart';
import '../screens/cart/direct_payment_screen.dart';
import '../screens/chat/create_group_screen.dart';
import '../screens/chat/friend_chat_screens.dart';
import '../screens/chat/messages_screens.dart';
import '../screens/product/product_detail_screen.dart';
import '../screens/shop/shop_shell.dart';
import '../screens/wallet/qr_pay_screens.dart';
import '../screens/live/watch_live_screen.dart';
import '../screens/store/seller_store_screen.dart';
import '../store/app_store.dart';
import '../models/models.dart';

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
      path.startsWith('/live/') ||
      path.startsWith('/app/') ||
      path.startsWith('/orders/') ||
      path.startsWith('/messages/');
}

String? _rewriteIncomingPath(Uri uri) {
  // cityshop://products/{slug} → /products/{slug}
  const deepLinkHosts = {'products', 'product', 'stores', 'store', 'live', 'app'};
  if (uri.scheme == 'cityshop' && deepLinkHosts.contains(uri.host)) {
    if (uri.host == 'app') {
      final target = _appLinkToInAppPath(uri.path);
      if (target == null) return null;
      if (uri.hasQuery) return '$target?${uri.query}';
      return target;
    }
    final host = switch (uri.host) {
      'store' => 'stores',
      'product' => 'products',
      _ => uri.host,
    };
    final path = uri.path.isEmpty ? '' : uri.path;
    final target = '/$host$path';
    if (uri.hasQuery) return '$target?${uri.query}';
    return target;
  }

  if (uri.path.startsWith('/app/')) {
    final target = _appLinkToInAppPath(uri.path);
    if (target == null) return null;
    if (uri.hasQuery) return '$target?${uri.query}';
    return target;
  }

  return null;
}

String? _appLinkToInAppPath(String path) {
  var rest = path;
  if (rest.startsWith('/app/')) {
    rest = rest.substring(4);
  }
  if (rest.startsWith('/product/') && !rest.startsWith('/products/')) {
    rest = '/products/${rest.substring('/product/'.length)}';
  } else if (rest.startsWith('/store/') && !rest.startsWith('/stores/')) {
    rest = '/stores/${rest.substring('/store/'.length)}';
  }
  if (rest.startsWith('/products/') ||
      rest.startsWith('/stores/') ||
      rest.startsWith('/live/')) {
    return rest;
  }
  return null;
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
        path: '/forgot-password',
        builder: (_, state) => ForgotPasswordScreen(
          initialLogin: state.extra is String ? state.extra as String : '',
        ),
      ),
      GoRoute(
        path: '/shop',
        builder: (_, state) => ShopShell(
          initialTab: _shellTabs[state.uri.queryParameters['tab']] ?? 0,
        ),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(path: '/wishlist', builder: (_, __) => const WishlistScreen()),
      GoRoute(path: '/following', builder: (_, __) => const FollowingScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/wallet/manual-deposit', builder: (_, __) => const ManualDepositScreen()),
      GoRoute(
        path: '/wallet/manual-deposit/:id',
        builder: (_, state) => ManualDepositStatusScreen(
          depositId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(path: '/wallet/withdraw', builder: (_, __) => const WithdrawScreen()),
      GoRoute(path: '/qr', builder: (_, __) => const QrPayHubScreen()),
      GoRoute(path: '/qr/scan', builder: (_, __) => const QrScanScreen()),
      GoRoute(path: '/qr/receive', builder: (_, __) => const QrReceiveScreen()),
      GoRoute(
        path: '/qr/contact',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Map) {
            final payload = extra['payload'] as String? ?? '';
            final resolved = extra['resolved'] is Map
                ? Map<String, dynamic>.from(extra['resolved'] as Map)
                : <String, dynamic>{};
            return QrContactScreen(payload: payload, resolved: resolved);
          }
          return const QrPayHubScreen();
        },
      ),
      GoRoute(
        path: '/qr/pay',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Map) {
            final payload = extra['payload'] as String? ?? '';
            final resolved = extra['resolved'] is Map
                ? Map<String, dynamic>.from(extra['resolved'] as Map)
                : <String, dynamic>{};
            return QrPayScreen(payload: payload, resolved: resolved);
          }
          return const QrPayHubScreen();
        },
      ),
      GoRoute(path: '/addresses', builder: (_, __) => const AddressesScreen()),
      GoRoute(path: '/profile/edit', builder: (_, __) => const ProfileEditScreen()),
      GoRoute(path: '/profile/password', builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(path: '/profile/payment-pin', builder: (_, __) => const PaymentPinScreen()),
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
        path: '/live/:slug',
        builder: (_, state) => WatchLiveScreen(slug: state.pathParameters['slug']!),
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
        path: '/messages/new',
        builder: (_, __) => const NewChatScreen(),
      ),
      GoRoute(
        path: '/messages/new-group',
        builder: (_, __) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '/messages/:id',
        builder: (_, state) => ChatScreen(
          conversationId: int.parse(state.pathParameters['id']!),
          attachProduct: state.extra is AttachProduct ? state.extra as AttachProduct : null,
        ),
      ),
    ],
    redirect: (context, state) {
      final uri = state.uri;
      final rewritten = _rewriteIncomingPath(uri);
      if (rewritten != null && rewritten != _locationWithQuery(state)) {
        return rewritten;
      }

      final loc = state.matchedLocation;
      final path = rewritten ?? uri.path;

      // Keep product/store deep links alive while splash boots — but never trap
      // the user on splash if they already skipped (finishBoot clears this).
      if (store.booting) {
        if (_isDeepLinkPath(path)) {
          pendingAfterBoot = rewritten ?? _locationWithQuery(state);
        }
        if (loc == '/splash') return null;
        // Allow Skip intro / forced entry into the main shell.
        if (loc == '/shop' || loc.startsWith('/shop')) return null;
        return '/splash';
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
