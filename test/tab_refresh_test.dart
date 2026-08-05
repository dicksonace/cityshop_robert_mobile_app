import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/wallet_orders_screens.dart';
import 'package:cityshop_mobile/store/app_store.dart';
import 'package:cityshop_mobile/widgets/tab_refresh.dart';

/// The shell builds every tab up front, so tabs are routinely created while
/// nobody is signed in yet. They have to fill themselves in once the buyer
/// logs in — before this, the data only showed up after killing the app.
class _FakeApiClient extends ApiClient {
  int orderCalls = 0;

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    if (path == '/orders') {
      orderCalls++;
      return Response(
        requestOptions: RequestOptions(path: path),
        data: {
          'data': [
            {
              'id': 1,
              'order_number': 'CS20260805',
              'status': 'shipped',
              'payment_status': 'paid',
              'payment_method': 'wallet',
              'total': 250.0,
              'created_at': '2026-08-05T10:00:00+00:00',
              'seller': {'store_name': 'City Unlock'},
              'items': [
                {
                  'id': 1,
                  'product_id': 1,
                  'product_name': 'Electric bike',
                  'quantity': 1,
                  'unit_price': 250.0,
                  'line_total': 250.0,
                  'status': 'shipped',
                },
              ],
            },
          ],
          'meta': {'current_page': 1, 'last_page': 1, 'per_page': 50, 'total': 1},
        },
      );
    }

    return Response(requestOptions: RequestOptions(path: path), data: const <String, dynamic>{});
  }
}

Future<void> _pumpOrders(WidgetTester tester, AppStore store) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/orders',
    routes: [
      GoRoute(path: '/orders', builder: (_, __) => const Scaffold(body: OrdersTab())),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tab built before login loads as soon as the buyer signs in', (tester) async {
    final api = _FakeApiClient();
    // Splash has finished restoring the session and found nobody signed in.
    final store = AppStore(api)..booting = false;

    await _pumpOrders(tester, store);

    expect(find.text('Electric bike'), findsNothing);
    expect(api.orderCalls, 0);

    store
      ..user = const AppUser(id: 1, name: 'Robert', email: 'r@example.com')
      ..notifyListeners();
    await tester.pumpAndSettle();

    expect(api.orderCalls, 1);
    expect(find.text('Electric bike'), findsOneWidget);
  });

  testWidgets('logging out and back in reloads the tab instead of keeping stale data',
      (tester) async {
    final api = _FakeApiClient();
    final store = AppStore(api)
      ..booting = false
      ..user = const AppUser(id: 1, name: 'Robert', email: 'r@example.com');

    await _pumpOrders(tester, store);
    expect(api.orderCalls, 1);

    store
      ..user = null
      ..orders = []
      ..notifyListeners();
    await tester.pumpAndSettle();

    store
      ..user = const AppUser(id: 2, name: 'Ama', email: 'a@example.com')
      ..notifyListeners();
    await tester.pumpAndSettle();

    expect(api.orderCalls, 2);
    expect(find.text('Electric bike'), findsOneWidget);
  });

  testWidgets('the visible tab refreshes itself every 20 seconds', (tester) async {
    final api = _FakeApiClient();
    final store = AppStore(api)
      ..booting = false
      ..user = const AppUser(id: 1, name: 'Robert', email: 'r@example.com');

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: const MaterialApp(
          home: ActiveTab(index: 2, child: Scaffold(body: OrdersTab())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.orderCalls, 1);

    await tester.pump(kTabAutoRefresh + const Duration(seconds: 1));
    await tester.pump();
    expect(api.orderCalls, 2);

    // Leave no timer running when the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reopening a tab pulls fresh data instead of showing what was left', (tester) async {
    final api = _FakeApiClient();
    final store = AppStore(api)
      ..booting = false
      ..user = const AppUser(id: 1, name: 'Robert', email: 'r@example.com');

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var index = 2;
    late void Function(void Function()) rebuild;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ActiveTab(index: index, child: const Scaffold(body: OrdersTab()));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.orderCalls, 1);

    rebuild(() => index = 1);
    await tester.pump();

    rebuild(() => index = 2);
    await tester.pump();
    await tester.pump();

    expect(api.orderCalls, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a tab that is not the visible one stays idle', (tester) async {
    final api = _FakeApiClient();
    final store = AppStore(api)
      ..booting = false
      ..user = const AppUser(id: 1, name: 'Robert', email: 'r@example.com');

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: const MaterialApp(
          // Wallet is on screen, so the orders tab must not fetch anything.
          home: ActiveTab(index: 1, child: Scaffold(body: OrdersTab())),
        ),
      ),
    );
    await tester.pump();

    expect(api.orderCalls, 0);
  });
}
