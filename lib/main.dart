import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'router/app_router.dart';
import 'services/push_notifications.dart';
import 'store/app_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) {
    return const Material(
      color: Color(0xFFF8FAFC),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This page could not load. Switch tabs and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  };
  final api = ApiClient();
  final store = AppStore(api);
  try {
    await PushNotifications.instance.init(store).timeout(const Duration(seconds: 5));
  } catch (_) {
    // Push must never block opening the app.
  }
  runApp(CityShopApp(store: store));
}

class CityShopApp extends StatefulWidget {
  const CityShopApp({super.key, required this.store});

  final AppStore store;

  @override
  State<CityShopApp> createState() => _CityShopAppState();
}

class _CityShopAppState extends State<CityShopApp> with WidgetsBindingObserver {
  late final router = createRouter(widget.store);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotifications.instance.init(
      widget.store,
      onOpenRoute: (route) {
        router.go(route);
      },
      currentPath: () => router.routeInformationProvider.value.uri.path,
    );
    unawaited(_bootstrapPush());
  }

  Future<void> _bootstrapPush() async {
    // Wait for auth boot so we only prompt / register for signed-in buyers.
    for (var i = 0; i < 40; i++) {
      if (!widget.store.booting) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || !widget.store.isLoggedIn) return;
    await PushNotifications.instance.syncForLoggedInUser(requestIfNeeded: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    PushNotifications.instance.setAppInForeground(state == AppLifecycleState.resumed);
    if (widget.store.isLoggedIn &&
        (state == AppLifecycleState.resumed || state == AppLifecycleState.paused)) {
      unawaited(PushNotifications.instance.pollAndNotify());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.store,
      child: MaterialApp.router(
        title: 'CityShop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.light,
        themeMode: ThemeMode.light,
        routerConfig: router,
      ),
    );
  }
}
