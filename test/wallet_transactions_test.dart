import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/wallet_orders_screens.dart';
import 'package:cityshop_mobile/store/app_store.dart';

/// The shape `GET /api/v1/wallet/transactions` returns.
const _ledger = {
  'data': [
    {
      'id': 2,
      'type': 'order_payment',
      'type_label': 'Order Payment',
      'amount': -100.0,
      'description': 'Order payment (Checkout CS20260731ABF6Z2)',
      'reference': 'PAY-CHKOUT-1',
      'created_at': '2026-07-31T10:04:00+00:00',
      'balance_before': 300.0,
      'balance_after': 200.0,
    },
    {
      'id': 1,
      'type': 'fund_added',
      'type_label': 'Funds Added',
      'amount': 300.0,
      'description': 'Funds added via momo',
      'reference': 'TOP-8W13ETRT3D4E',
      'created_at': '2026-07-31T09:57:00+00:00',
      'balance_before': 0.0,
      'balance_after': 300.0,
    },
  ],
  'meta': {'current_page': 1, 'last_page': 2, 'per_page': 20, 'total': 25},
};

class _FakeApiClient extends ApiClient {
  final requestedPages = <Object?>[];

  Response<dynamic> _ok(String path, Object? data) =>
      Response(requestOptions: RequestOptions(path: path), data: data);

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) async {
    switch (path) {
      case '/wallet':
        return _ok(path, {
          'data': {'available_balance': 200.0, 'pending_balance': 0.0},
        });
      case '/wallet/manual-funding':
        return _ok(path, {'enabled': false, 'accounts': <dynamic>[]});
      case '/wallet/transactions':
        requestedPages.add(query?['page']);
        return _ok(path, _ledger);
    }
    return _ok(path, const <String, dynamic>{});
  }
}

Future<AppStore> _pumpWallet(WidgetTester tester, _FakeApiClient api) async {
  final store = AppStore(api)
    ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: const MaterialApp(home: Scaffold(body: WalletTab())),
    ),
  );
  await tester.pumpAndSettle();

  return store;
}

void main() {
  testWidgets('wallet lists the ledger with amounts and running balances', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpWallet(tester, _FakeApiClient());

    expect(find.text('Transaction History'), findsOneWidget);

    expect(find.text('Funds Added'), findsOneWidget);
    expect(find.text('Order Payment'), findsOneWidget);
    expect(find.text('TOP-8W13ETRT3D4E'), findsOneWidget);
    expect(find.text('Funds added via momo'), findsOneWidget);

    // Credits are signed, debits keep the minus the API sent.
    expect(find.text('+GH₵300.00'), findsOneWidget);
    expect(find.text('-GH₵100.00'), findsOneWidget);

    expect(find.text('Before balance'), findsNWidgets(2));
    expect(find.text('After balance'), findsNWidgets(2));
  });

  testWidgets('load more asks for the next page', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final api = _FakeApiClient();
    await _pumpWallet(tester, api);

    expect(api.requestedPages, [1]);

    final loadMore = find.text('Load more');
    await tester.ensureVisible(loadMore);
    await tester.pumpAndSettle();
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(api.requestedPages, [1, 2]);
  });
}
