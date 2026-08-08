import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/wallet_orders_screens.dart';
import 'package:cityshop_mobile/store/app_store.dart';

/// Height of the Android three-button navigation bar Robert's phone shows.
const _navBar = 48.0;

/// Roughly what a soft keyboard covers on a short phone.
const _keyboard = 260.0;

const _order = {
  'id': 1,
  'order_number': 'CS20260731D4096A',
  'status': 'shipped',
  'payment_status': 'paid',
  'payment_method': 'wallet',
  'total': 4200.0,
  'created_at': '2026-07-31T14:02:00+00:00',
  'receiver_name': 'Kofi amoah',
  'receiver_phone': '0539790093',
  'city': 'Sefwi Bekwai',
  'region': 'Western North',
  'items': [
    {
      'id': 11,
      'product_name': 'Electric bike',
      'quantity': 1,
      'unit_price': 4200.0,
      'line_total': 4200.0,
      'status': 'delivered',
      'image_url': null,
      'can_request_refund': true,
      'can_review': true,
    },
  ],
};

class _FakeApiClient extends ApiClient {
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) async =>
      Response(
        requestOptions: RequestOptions(path: path),
        data: path == '/orders/1' ? {'data': _order} : const <String, dynamic>{},
      );
}

/// Ignores noise unrelated to sheet height: the order card's "ListTile inside a
/// coloured DecoratedBox" warning, and horizontal overflow, which only happens
/// because the test font is wider than the one the phone uses. Vertical
/// overflow stays fatal — that is the clipping these tests are about.
void _ignoreUnrelatedWarnings() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('ListTile background color')) return;
    if (message.contains('overflowed') && message.contains('on the right')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Opens the order screen straight into the refund sheet, on a short screen
/// with a navigation bar and optionally a raised keyboard.
Future<double> _openRefundSheet(WidgetTester tester, {bool keyboardOpen = false}) async {
  _ignoreUnrelatedWarnings();
  tester.view.physicalSize = const Size(1080, 1560);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final store = AppStore(_FakeApiClient())
    ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            viewPadding: const EdgeInsets.only(bottom: _navBar),
            padding: EdgeInsets.only(bottom: keyboardOpen ? 0 : _navBar),
            viewInsets: EdgeInsets.only(bottom: keyboardOpen ? _keyboard : 0),
          ),
          child: child!,
        ),
        home: const OrderDetailScreen(orderId: 1, initialAction: 'refund'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Request a refund'), findsOneWidget);

  return tester.view.physicalSize.height / tester.view.devicePixelRatio;
}

void main() {
  testWidgets('the refund button sits above the navigation bar', (tester) async {
    final screenHeight = await _openRefundSheet(tester);

    final button = find.widgetWithText(ElevatedButton, 'Submit request');
    expect(button, findsOneWidget);

    // Nothing of the red button may fall into the navigation bar strip.
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(screenHeight - _navBar));
  });

  testWidgets('the refund button stays visible while typing', (tester) async {
    final screenHeight = await _openRefundSheet(tester, keyboardOpen: true);

    final button = find.widgetWithText(ElevatedButton, 'Submit request');
    expect(button, findsOneWidget);

    final bottom = tester.getBottomRight(button).dy;
    expect(bottom, lessThanOrEqualTo(screenHeight - _keyboard));
    expect(tester.getTopLeft(button).dy, greaterThan(0));

    // The form scrolls instead of pushing the button off screen.
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Wrong item received'), findsOneWidget);
  });

  testWidgets('the review button sits above the navigation bar too', (tester) async {
    _ignoreUnrelatedWarnings();
    tester.view.physicalSize = const Size(1080, 1560);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = AppStore(_FakeApiClient())
      ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewPadding: const EdgeInsets.only(bottom: _navBar),
              padding: const EdgeInsets.only(bottom: _navBar),
            ),
            child: child!,
          ),
          home: const OrderDetailScreen(orderId: 1, initialAction: 'review'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final button = find.widgetWithText(ElevatedButton, 'Submit review');
    expect(button, findsOneWidget);
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(screenHeight - _navBar));
  });
}
