import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'router/app_router.dart';
import 'store/app_store.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final store = AppStore(api);
  runApp(CityShopApp(store: store));
}

class CityShopApp extends StatelessWidget {
  const CityShopApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final router = createRouter(store);

    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp.router(
        title: 'CityShop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    );
  }
}
