import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/product/product_detail_screen.dart';
import '../screens/shop/shop_shell.dart';
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
      GoRoute(
        path: '/products/:slug',
        builder: (_, state) => ProductDetailScreen(slug: state.pathParameters['slug']!),
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
