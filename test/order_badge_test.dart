import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/shop/shop_shell.dart';
import 'package:cityshop_mobile/store/app_store.dart';

Map<String, dynamic> _order(int id, String status) => {
      'id': id,
      'order_number': 'CS2026073$id',
      'status': status,
      'payment_status': 'paid',
      'payment_method': 'wallet',
      'total': 40.0,
      'created_at': '2026-07-31T10:00:00+00:00',
      'items': <dynamic>[],
    };

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.activeOrders = 3, this.totalOrders = 12, this.listedTotal = 9});

  final int activeOrders;
  final int totalOrders;

  /// Paginator total for `GET /orders`; four orders come back on the page.
  final int listedTotal;

  Response<dynamic> _ok(String path, Object? data) =>
      Response(requestOptions: RequestOptions(path: path), data: data);

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) async {
    switch (path) {
      case '/notifications/counts':
        return _ok(path, {
          'unread_messages': 0,
          'unread_notifications': 4,
          'active_orders': activeOrders,
          'total_orders': totalOrders,
        });
      case '/orders':
        return _ok(path, {
          'data': [
            _order(1, 'shipped'),
            _order(2, 'awaiting_confirmation'),
            _order(3, 'delivered'),
            _order(4, 'cancelled'),
          ],
          'meta': {'current_page': 1, 'last_page': 1, 'per_page': 50, 'total': listedTotal},
        });
    }
    return _ok(path, const <String, dynamic>{});
  }
}

/// Reads the badge the bottom bar draws over the "My Order" icon.
Badge _orderBadge(WidgetTester tester) {
  final icon = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byIcon(Icons.inventory_2_outlined),
  );

  return tester.widget<Badge>(
    find.ancestor(of: icon, matching: find.byType(Badge)).first,
  );
}

/// ShopShell keeps every tab alive in an IndexedStack, so pumping it also mounts
/// cards that trip Material's "ListTile inside a coloured DecoratedBox" warning.
/// That is unrelated to the badge, so let it through instead of failing the test.
void _ignoreListTileWarnings() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('ListTile background color')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<AppStore> _pumpShell(WidgetTester tester, ApiClient api, {bool loggedIn = true}) async {
  _ignoreListTileWarnings();

  final store = AppStore(api);
  if (loggedIn) {
    store.user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');
  }

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: MaterialApp(
        home: const ShopShell(),
        theme: ThemeData(useMaterial3: true),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }

  return store;
}

void main() {
  testWidgets('My Order tab shows how many orders are still open', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpShell(tester, _FakeApiClient());

    final badge = _orderBadge(tester);
    expect(badge.isLabelVisible, isTrue);
    expect((badge.label as Text).data, '3');
  });

  testWidgets('no badge when the buyer has nothing open', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpShell(tester, _FakeApiClient(activeOrders: 0, totalOrders: 6));

    expect(_orderBadge(tester).isLabelVisible, isFalse);
  });

  testWidgets('signed out buyers never see the badge', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final store = await _pumpShell(tester, _FakeApiClient(), loggedIn: false);
    expect(store.activeOrders, 0);
    expect(_orderBadge(tester).isLabelVisible, isFalse);
  });

  testWidgets('counts above nine collapse to 9+', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpShell(tester, _FakeApiClient(activeOrders: 14, totalOrders: 20));

    expect((_orderBadge(tester).label as Text).data, '9+');
  });

  test('a complete order list retallies the badge from the fetched orders', () async {
    final store = AppStore(_FakeApiClient(listedTotal: 4))
      ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

    await store.loadOrders();

    // shipped + awaiting_confirmation are open; delivered and cancelled are not.
    expect(store.activeOrders, 2);
    expect(store.totalOrders, 4);
  });

  test('a partial order page leaves the server tally alone', () async {
    final store = AppStore(_FakeApiClient(activeOrders: 31, listedTotal: 60))
      ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

    await store.refreshNotificationCounts();
    await store.loadOrders();

    expect(store.activeOrders, 31);
    expect(store.totalOrders, 60);
  });
}
