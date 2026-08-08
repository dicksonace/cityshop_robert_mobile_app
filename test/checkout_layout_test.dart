import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/cart/checkout_screen.dart';
import 'package:cityshop_mobile/store/app_store.dart';

Map<String, dynamic> _address(int id, String first, {bool isDefault = false}) => {
      'id': id,
      'first_name': first,
      'last_name': 'Amoah',
      'phone': '0539790093',
      'address_line': 'Bekwai main station',
      'city': 'Sefwi Bekwai',
      'region': 'Western North',
      'is_default': isDefault,
    };

final _preview = <String, dynamic>{
  'subtotal': 300.0,
  'shipping_total': 30.0,
  'grand_total': 330.0,
  'wallet': {'available_balance': 1040.0},
  'paystack_configured': true,
  'addresses': [_address(1, 'Kofi', isDefault: true), _address(2, 'Ama')],
  'seller_groups': [
    {
      'seller_id': 9,
      'seller_name': 'City Unlock',
      'package_total': 330.0,
      'accept_marketplace_payments': true,
      'accept_direct_payments': true,
      'payment_methods': [
        {'id': 4, 'display_label': 'MTN Mobile Money — 0248520718 · Robert Asare'},
        {'id': 5, 'display_label': 'Fidelity Bank — 1010203040 · Robert Asare'},
      ],
    },
  ],
};

class _FakeApiClient extends ApiClient {
  _FakeApiClient({Map<String, dynamic>? preview}) : preview = preview ?? _preview;

  final Map<String, dynamic> preview;
  final List<Map<String, dynamic>> posted = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) async {
    return Response(requestOptions: RequestOptions(path: path), data: preview);
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    int maxAttempts = 2,
  }) async {
    posted.add({'path': path, 'data': data});
    return Response(
      requestOptions: RequestOptions(path: path),
      data: const {'next': 'orders', 'message': 'Order placed'},
    );
  }
}

Future<_FakeApiClient> _pumpCheckout(
  WidgetTester tester, {
  Map<String, dynamic>? preview,
}) async {
  tester.view.physicalSize = const Size(1080, 2100);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final api = _FakeApiClient(preview: preview);
  final store = AppStore(api)..user = const AppUser(id: 1, name: 'Robert', email: 'r@example.com');

  final router = GoRouter(
    initialLocation: '/checkout',
    routes: [
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(path: '/shop', builder: (_, __) => const Scaffold(body: Text('shop'))),
      GoRoute(path: '/addresses', builder: (_, __) => const Scaffold(body: Text('addresses'))),
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

  return api;
}

void main() {
  testWidgets('the whole checkout fits on one screen with the total in reach', (tester) async {
    await _pumpCheckout(tester);

    // Nothing is scrolled away: address, all three methods, seller choice, total.
    expect(find.text('Kofi Amoah'), findsOneWidget);
    expect(find.text('Mobile Money / Card'), findsOneWidget);
    expect(find.text('CityShop Wallet'), findsOneWidget);
    expect(find.text('Cash on delivery'), findsOneWidget);
    expect(find.text('Paying City Unlock'), findsOneWidget);
    expect(find.text('Place order'), findsOneWidget);

    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final button = tester.getRect(find.text('Place order'));
    expect(button.bottom, lessThan(screen));
  });

  testWidgets('the pay bar keeps the total next to the button', (tester) async {
    await _pumpCheckout(tester);

    final total = find.text('GH₵330.00');
    // The seller pill and the summary show it too; the bar is the last one.
    expect(total, findsAtLeastNWidgets(2));

    final inBar = tester.getRect(total.last);
    final button = tester.getRect(find.text('Place order'));
    expect((inBar.center.dy - button.center.dy).abs(), lessThan(20));
  });

  testWidgets('picking a payment method moves the tick', (tester) async {
    await _pumpCheckout(tester);

    await tester.tap(find.text('Cash on delivery'));
    await tester.pumpAndSettle();

    // Cash hides the per-seller choice, since there is nothing to pay online.
    expect(find.text('Paying City Unlock'), findsNothing);

    await tester.tap(find.text('CityShop Wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Balance GH₵1,040.00'), findsOneWidget);
    expect(find.text('Paying City Unlock'), findsOneWidget);
  });

  testWidgets('a short wallet balance says so', (tester) async {
    await _pumpCheckout(tester, preview: {
      ..._preview,
      'wallet': const {'available_balance': 12.0},
    });

    expect(find.text('GH₵12.00 · not enough'), findsOneWidget);
  });

  testWidgets('the seller switch swaps between CityShop and direct pay', (tester) async {
    await _pumpCheckout(tester);

    expect(find.text('Held by CityShop until you get the item'), findsOneWidget);
    expect(find.textContaining('MTN Mobile Money'), findsNothing);

    await tester.tap(find.text('Pay seller'));
    await tester.pumpAndSettle();

    expect(find.text('Send the money yourself, then upload the proof'), findsOneWidget);
    expect(find.textContaining('MTN Mobile Money'), findsOneWidget);
    expect(find.textContaining('Fidelity Bank'), findsOneWidget);
  });

  testWidgets('choosing another delivery address swaps the card', (tester) async {
    await _pumpCheckout(tester);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Bekwai main station').last);
    await tester.pumpAndSettle();

    expect(find.text('Ama Amoah'), findsOneWidget);
    expect(find.text('Kofi Amoah'), findsNothing);
  });

  testWidgets('a single address offers Edit instead of the picker', (tester) async {
    await _pumpCheckout(tester, preview: {
      ..._preview,
      'addresses': [_address(1, 'Kofi', isDefault: true)],
    });

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('with no address saved the card asks for one', (tester) async {
    await _pumpCheckout(tester, preview: {..._preview, 'addresses': const []});

    expect(find.text('Add a delivery address'), findsOneWidget);
    expect(find.text('Place order'), findsOneWidget);
  });

  testWidgets('a store that stopped taking cash blocks the cash option', (tester) async {
    final api = await _pumpCheckout(tester, preview: {
      ..._preview,
      'seller_groups': [
        {...(_preview['seller_groups'] as List).first as Map<String, dynamic>, 'accepts_cash': false},
      ],
    });

    expect(find.text('City Unlock does not take cash'), findsOneWidget);

    await tester.tap(find.text('Cash on delivery'));
    await tester.pumpAndSettle();

    // The tap is ignored, so the seller payment choice stays on screen.
    expect(find.text('Paying City Unlock'), findsOneWidget);

    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();

    expect((api.posted.single['data'] as Map)['payment_method'], 'momo');
  });

  testWidgets('cash stays available while the store allows it', (tester) async {
    await _pumpCheckout(tester, preview: {
      ..._preview,
      'seller_groups': [
        {...(_preview['seller_groups'] as List).first as Map<String, dynamic>, 'accepts_cash': true},
      ],
    });

    await tester.tap(find.text('Cash on delivery'));
    await tester.pumpAndSettle();

    expect(find.text('Pay when it arrives'), findsOneWidget);
    expect(find.text('Paying City Unlock'), findsNothing);
  });

  testWidgets('placing the order still sends the seller payment choice', (tester) async {
    final api = await _pumpCheckout(tester);

    await tester.tap(find.text('Pay seller'));
    await tester.pumpAndSettle();

    // The account list sits below the trust notice, so scroll to it first.
    await tester.scrollUntilVisible(
      find.textContaining('Fidelity Bank'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Fidelity Bank'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Fidelity Bank'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();

    final body = api.posted.single['data'] as Map;
    expect(body['address_id'], 1);
    expect(body['payment_method'], 'momo');
    expect(body['seller_payments'], {
      '9': {'channel': 'direct', 'method_id': 5},
    });
  });
}
