import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/wallet_orders_screens.dart';
import 'package:cityshop_mobile/store/app_store.dart';

/// A "pay the seller directly" order: the payment stays pending until the seller
/// confirms the transfer, so only the proof fields tell us the buyer has paid.
Map<String, dynamic> _directOrder({
  int id = 1,
  String status = 'processing',
  String? reference,
  String? proof,
  String? rejection,
  String paymentStatus = 'pending',
}) =>
    {
      'id': id,
      'order_number': 'CS20260801$id',
      'status': status,
      'payment_status': paymentStatus,
      'payment_channel': 'direct',
      'payment_method': 'momo',
      'total': 350.0,
      'created_at': '2026-08-01T10:00:00+00:00',
      'direct_payment_reference': reference,
      'direct_payment_proof_path': proof,
      'direct_payment_submitted': reference != null || proof != null,
      'direct_payment_confirmed_at': null,
      'direct_payment_rejection_reason': rejection,
      'seller': {'id': 9, 'store_name': 'City Unlock'},
      'items': [
        {
          'id': 11,
          'product_name': 'iphone 12',
          'quantity': 1,
          'unit_price': 350.0,
          'status': status,
        },
      ],
    };

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.orders);

  final List<Map<String, dynamic>> orders;

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final data = path == '/orders'
        ? {
            'data': orders,
            'meta': {
              'current_page': 1,
              'last_page': 1,
              'per_page': 50,
              'total': orders.length,
            },
          }
        : const <String, dynamic>{};

    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}

Future<void> _pumpOrders(WidgetTester tester, List<Map<String, dynamic>> orders) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final store = AppStore(_FakeApiClient(orders))
    ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: OrdersTab()),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  group('order card status for direct seller payments', () {
    testWidgets('a submitted transfer reads as Processing, not Awaiting payment',
        (tester) async {
      await _pumpOrders(tester, [_directOrder(reference: 'MP2608010001')]);

      expect(find.text('Awaiting payment'), findsNothing);
      expect(find.text('Processing'), findsWidgets);
      expect(
        find.text('Payment sent · waiting for the seller to confirm'),
        findsOneWidget,
      );
    });

    testWidgets('an uploaded screenshot alone also counts as submitted', (tester) async {
      await _pumpOrders(tester, [
        _directOrder(proof: 'direct-payment-proofs/abc.jpg'),
      ]);

      expect(find.text('Awaiting payment'), findsNothing);
      expect(
        find.text('Payment sent · waiting for the seller to confirm'),
        findsOneWidget,
      );
    });

    testWidgets('nothing sent yet still asks the buyer to pay', (tester) async {
      await _pumpOrders(tester, [_directOrder()]);

      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.text('Waiting for payment'), findsOneWidget);
    });

    testWidgets('a rejected transfer asks the buyer to send it again', (tester) async {
      await _pumpOrders(tester, [
        _directOrder(reference: 'MP2608010001', rejection: 'Wrong amount'),
      ]);

      expect(find.text('Payment declined'), findsOneWidget);
      expect(find.text('Payment not confirmed · tap to send it again'), findsOneWidget);
    });

    testWidgets('fulfillment progress still wins once the seller ships', (tester) async {
      await _pumpOrders(tester, [
        _directOrder(status: 'shipped', reference: 'MP2608010001'),
      ]);

      expect(find.text('Awaiting payment'), findsNothing);
      expect(find.text('Out for delivery'), findsWidgets);
    });
  });

  group('OrderModel', () {
    test('treats a reference or proof as a submitted direct payment', () {
      expect(
        OrderModel.fromJson(_directOrder(reference: 'MP1')).directPaymentUnderReview,
        isTrue,
      );
      expect(
        OrderModel.fromJson(_directOrder(proof: 'p.jpg')).directPaymentUnderReview,
        isTrue,
      );
      expect(OrderModel.fromJson(_directOrder()).directPaymentUnderReview, isFalse);
    });

    test('falls back to the proof fields when the flag is missing', () {
      final json = _directOrder(reference: 'MP1')..remove('direct_payment_submitted');

      expect(OrderModel.fromJson(json).directPaymentSubmitted, isTrue);
    });

    test('a rejected transfer is not under review', () {
      final order = OrderModel.fromJson(
        _directOrder(reference: 'MP1', rejection: 'Wrong amount'),
      );

      expect(order.directPaymentRejected, isTrue);
      expect(order.directPaymentUnderReview, isFalse);
    });

    test('a cancelled or paid order is not under review', () {
      expect(
        OrderModel.fromJson(_directOrder(reference: 'MP1', status: 'cancelled'))
            .directPaymentUnderReview,
        isFalse,
      );
      expect(
        OrderModel.fromJson(_directOrder(reference: 'MP1', paymentStatus: 'paid'))
            .directPaymentUnderReview,
        isFalse,
      );
    });
  });
}
