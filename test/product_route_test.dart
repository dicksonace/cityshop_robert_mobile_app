import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/router/app_router.dart';
import 'package:cityshop_mobile/store/app_store.dart';

class _IdleApiClient extends ApiClient {
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) async {
    return Response(requestOptions: RequestOptions(path: path), data: const <String, dynamic>{});
  }
}

/// Follows [link] through the real router and reports where it landed.
Future<String> _follow(WidgetTester tester, GoRouter router, String link) async {
  router.go(link);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  final config = router.routerDelegate.currentConfiguration;
  return config.isError ? 'error' : config.uri.path;
}

void main() {
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final store = AppStore(_IdleApiClient())..booting = false;
    final router = createRouter(store);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    return router;
  }

  testWidgets('a singular product link still opens a product', (tester) async {
    final router = await pumpApp(tester);

    // What the older chat header sent, and what a shared web link can look like.
    expect(await _follow(tester, router, '/product/9'), '/products/9');
    expect(find.text('Page Not Found'), findsNothing);

    expect(await _follow(tester, router, '/product/honda-civic-2016'), '/products/honda-civic-2016');
    expect(find.text('Page Not Found'), findsNothing);
  });

  testWidgets('an app-shared product link opens the product in the app', (tester) async {
    final router = await pumpApp(tester);

    expect(await _follow(tester, router, '/app/products/honda-civic-2016'), '/products/honda-civic-2016');
    expect(await _follow(tester, router, '/app/store/city-unlock'), '/stores/city-unlock');
    expect(await _follow(tester, router, '/app/live/city-unlock'), '/live/city-unlock');
  });

  testWidgets('the plural product link is untouched', (tester) async {
    final router = await pumpApp(tester);

    expect(await _follow(tester, router, '/products/honda-civic-2016'), '/products/honda-civic-2016');
  });

  testWidgets('a singular store link still opens a store', (tester) async {
    final router = await pumpApp(tester);

    expect(await _follow(tester, router, '/store/city-unlock'), '/stores/city-unlock');
  });

  testWidgets('an unknown path is the only thing that errors', (tester) async {
    final router = await pumpApp(tester);

    expect(await _follow(tester, router, '/nope/9'), 'error');
  });
}
