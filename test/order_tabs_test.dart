import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/wallet_orders_screens.dart';
import 'package:cityshop_mobile/store/app_store.dart';

Map<String, dynamic> _item(
  int id,
  String name,
  String status, {
  bool canReview = false,
}) =>
    {
      'id': id,
      'product_id': id,
      'product_name': name,
      'quantity': 1,
      'unit_price': 250.0,
      'line_total': 250.0,
      'status': status,
      'can_review': canReview,
    };

Map<String, dynamic> _order(
  int id,
  String status, {
  String paymentStatus = 'paid',
  List<Map<String, dynamic>>? items,
}) =>
    {
      'id': id,
      'order_number': 'CS2026080$id',
      'status': status,
      'payment_status': paymentStatus,
      'payment_method': 'wallet',
      'total': 250.0,
      'created_at': '2026-08-01T10:00:00+00:00',
      'seller': {'store_name': 'City Unlock'},
      'items': items ?? [_item(id, 'Electric bike', status)],
    };

/// A finished order, an order the buyer still has to confirm, and one in transit.
final _orders = <Map<String, dynamic>>[
  _order(1, 'delivered', items: [_item(1, 'Electric bike', 'delivered')]),
  _order(2, 'delivered', items: [_item(2, 'Phone case', 'delivered', canReview: true)]),
  _order(3, 'awaiting_confirmation', items: [_item(3, 'Laptop bag', 'awaiting_confirmation')]),
  _order(4, 'shipped', items: [_item(4, 'Headphones', 'shipped')]),
];

class _FakeApiClient extends ApiClient {
  _FakeApiClient({List<Map<String, dynamic>>? orders}) : orders = orders ?? _orders;

  final List<Map<String, dynamic>> orders;

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final data = path == '/orders'
        ? {
            'data': orders,
            'meta': {'current_page': 1, 'last_page': 1, 'per_page': 50, 'total': orders.length},
          }
        : const <String, dynamic>{};

    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}

Future<void> _pumpOrders(WidgetTester tester, {List<Map<String, dynamic>>? orders}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final store = AppStore(_FakeApiClient(orders: orders))
    ..user = const AppUser(id: 1, name: 'Robert', email: 'r@example.com');

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

/// The hub tile for [label], which is where the badge counts live.
Finder _hubTile(String label) => find.ancestor(
      of: find.descendant(of: find.byType(GridView), matching: find.text(label)),
      matching: find.byType(InkWell),
    );

/// Reads the red badge on a hub tile; tiles without a badge count as zero.
String _hubCount(WidgetTester tester, String label) {
  final texts = tester
      .widgetList<Text>(find.descendant(of: _hubTile(label).first, matching: find.byType(Text)))
      .map((t) => t.data)
      .where((t) => t != label);

  return texts.isEmpty ? '0' : texts.first!;
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(_hubTile(label).first);
  await tester.pumpAndSettle();
}

/// Where the status tab strip sits on screen; the order list starts under it.
double _stripTop(WidgetTester tester, String allLabel) =>
    tester.getTopLeft(find.text(allLabel)).dy;

double _screenWidth(WidgetTester tester) =>
    tester.view.physicalSize.width / tester.view.devicePixelRatio;

void main() {
  testWidgets('Confirm only counts orders still waiting on the buyer', (tester) async {
    await _pumpOrders(tester);

    // Two delivered orders must not inflate Confirm.
    expect(_hubCount(tester, 'Confirm'), '1');
    expect(_hubCount(tester, 'Completed'), '2');
  });

  testWidgets('a completed order does not show under Confirm', (tester) async {
    await _pumpOrders(tester);

    await _openTab(tester, 'Confirm');

    expect(find.text('Laptop bag'), findsOneWidget);
    expect(find.text('Electric bike'), findsNothing);
    expect(find.text('Phone case'), findsNothing);
  });

  testWidgets('Completed keeps the finished orders', (tester) async {
    await _pumpOrders(tester);

    await _openTab(tester, 'Completed');

    expect(find.text('Electric bike'), findsOneWidget);
    expect(find.text('Phone case'), findsOneWidget);
    expect(find.text('Laptop bag'), findsNothing);
  });

  testWidgets('Review lists only what has not been rated yet', (tester) async {
    await _pumpOrders(tester);

    expect(_hubCount(tester, 'Review'), '1');

    await _openTab(tester, 'Review');

    expect(find.text('Phone case'), findsOneWidget);
    expect(find.text('Electric bike'), findsNothing);
  });

  testWidgets('an unconfirmed item inside a shipped order still asks for confirmation',
      (tester) async {
    await _pumpOrders(tester, orders: [
      _order(5, 'shipped', items: [
        _item(51, 'Charger', 'shipped'),
        _item(52, 'Speaker', 'awaiting_confirmation'),
      ]),
    ]);

    expect(_hubCount(tester, 'Confirm'), '1');
    expect(_hubCount(tester, 'Completed'), '0');
  });

  testWidgets('View all pulls the order list up to the top of the screen', (tester) async {
    await _pumpOrders(tester, orders: [
      for (var i = 1; i <= 12; i++)
        _order(i, 'delivered', items: [_item(i, 'Item $i', 'delivered')]),
    ]);

    // The list starts well below the hub cards.
    expect(_stripTop(tester, 'All (12)'), greaterThan(300));

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    expect(_stripTop(tester, 'All (12)'), lessThan(30));
    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('a hub shortcut scrolls its own tab into view', (tester) async {
    await _pumpOrders(tester);

    // Review sits off the right edge of the tab strip until it is picked.
    expect(tester.getTopLeft(find.text('Review (1)')).dx, greaterThan(_screenWidth(tester)));
    final before = _stripTop(tester, 'All (4)');

    await _openTab(tester, 'Review');

    final tab = tester.getRect(find.text('Review (1)'));
    expect(tab.left, greaterThanOrEqualTo(0));
    expect(tab.right, lessThanOrEqualTo(_screenWidth(tester)));
    expect(_stripTop(tester, 'All (4)'), lessThan(before));
  });

  testWidgets('nothing to confirm reads as zero', (tester) async {
    await _pumpOrders(tester, orders: [
      _order(6, 'delivered', items: [_item(61, 'Kettle', 'delivered')]),
    ]);

    expect(_hubCount(tester, 'Confirm'), '0');
    expect(_hubCount(tester, 'Completed'), '1');
  });
}
