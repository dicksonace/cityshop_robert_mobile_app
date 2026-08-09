import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/wallet_orders_screens.dart';
import 'package:cityshop_mobile/screens/account/withdraw_screen.dart';
import 'package:cityshop_mobile/store/app_store.dart';

/// The shape `GET /api/v1/wallet/withdrawals` returns.
Map<String, dynamic> _overview({
  double available = 1040,
  bool hasPending = false,
  List<Map<String, dynamic>> items = const [],
}) =>
    {
      'data': items,
      'summary': {
        'available_balance': available,
        'pending_balance': 0.0,
        'withdrawn_amount': 0.0,
        'minimum': 10,
        'has_pending': hasPending,
        'default_momo_number': '0539790093',
        'default_account_name': 'Robert Asare',
      },
    };

const _paidRequest = {
  'id': 8,
  'amount': 300.0,
  'momo_number': '0539790093',
  'account_name': 'Robert Asare',
  'network': 'telecel',
  'network_label': 'Telecel Cash',
  'status': 'paid',
  'status_label': 'Paid out',
  'rejection_reason': null,
  'created_at': '2026-07-30T09:00:00+00:00',
  'processed_at': '2026-07-30T09:41:00+00:00',
};

const _rejectedRequest = {
  'id': 9,
  'amount': 75.0,
  'momo_number': '0539790093',
  'account_name': 'Robert Asare',
  'network': 'mtn',
  'network_label': 'MTN Mobile Money',
  'status': 'rejected',
  'status_label': 'Rejected',
  'rejection_reason': 'Name did not match the MoMo account.',
  'created_at': '2026-07-29T09:00:00+00:00',
  'processed_at': '2026-07-29T10:00:00+00:00',
};

class _FakeApiClient extends ApiClient {
  _FakeApiClient({Map<String, dynamic>? overview}) : overview = overview ?? _overview();

  final Map<String, dynamic> overview;
  final List<String> gets = [];
  final List<(String, Map<String, dynamic>)> posts = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) async {
    gets.add(path);
    final data = switch (path) {
      '/wallet/withdrawals' => overview,
      '/wallet' => {
          'data': {
            'available_balance': 1040.0,
            'pending_balance': 0.0,
            'paystack_configured': true,
            'manual_top_up_enabled': true,
          },
        },
      '/wallet/transactions' => {'data': [], 'meta': {'current_page': 1, 'last_page': 1}},
      _ => const <String, dynamic>{},
    };

    return Response(requestOptions: RequestOptions(path: path), data: data);
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    int maxAttempts = 2,
  }) async {
    final body = Map<String, dynamic>.from(data as Map);
    posts.add((path, body));

    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
      data: {
        'message': 'Withdrawal request submitted.',
        'data': {
          'id': 11,
          'amount': body['amount'],
          'momo_number': body['momo_number'],
          'account_name': body['account_name'],
          'network': body['network'],
          'network_label': 'MTN Mobile Money',
          'status': 'pending',
          'status_label': 'Processing',
          'created_at': '2026-08-01T15:30:00+00:00',
        },
        'wallet': {'available_balance': 540.0, 'pending_balance': 0.0},
      },
    );
  }
}

Future<AppStore> _pumpWithdraw(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1170, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final store = AppStore(api)
    ..user = const AppUser(
      id: 1,
      name: 'Robert Asare',
      email: 'robert@example.com',
      // Submitting now stops at a payment PIN prompt, and refuses outright
      // when the account has no PIN set.
      hasPaymentPin: true,
    );

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: const MaterialApp(home: WithdrawScreen()),
    ),
  );
  await tester.pumpAndSettle();

  return store;
}

/// The form is taller than a phone viewport, so scroll a button into view the
/// way a user would before tapping it.
Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Fills the amount and opens the review sheet.
Future<void> _requestAmount(WidgetTester tester, String amount) async {
  await tester.enterText(find.widgetWithText(TextField, 'Amount (GH₵)'), amount);
  await _tapButton(tester, 'Review withdrawal');
}

/// Taps through the PIN pad that confirms a withdrawal. The pad pops itself
/// once the fourth digit lands.
Future<void> _enterPin(WidgetTester tester, [String pin = '1234']) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('the wallet card offers a withdraw action', (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = AppStore(_FakeApiClient())
      ..user = const AppUser(id: 1, name: 'Robert Asare', email: 'robert@example.com');

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: const MaterialApp(home: Scaffold(body: WalletTab())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Withdrawal'), findsOneWidget);
    expect(find.text('Recharge'), findsOneWidget);
    // Both actions sit on the balance card, above transaction history.
    expect(
      tester.getCenter(find.text('Withdrawal')).dy,
      lessThan(tester.getCenter(find.text('Transaction History')).dy),
    );
  });

  testWidgets('the screen prefills the buyer MoMo details and balance', (tester) async {
    await _pumpWithdraw(tester, _FakeApiClient());

    expect(find.text('Available to withdraw'), findsOneWidget);
    expect(find.text('GH₵1,040.00'), findsOneWidget);
    expect(find.widgetWithText(TextField, '0539790093'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Robert Asare'), findsOneWidget);
    expect(find.textContaining('Minimum GH₵10.00'), findsOneWidget);
  });

  testWidgets('"Withdraw all" fills the whole available balance', (tester) async {
    await _pumpWithdraw(tester, _FakeApiClient());

    await tester.tap(find.text('Withdraw all'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '1040.00'), findsOneWidget);
  });

  testWidgets('a request under the minimum never reaches the server', (tester) async {
    final api = _FakeApiClient();
    await _pumpWithdraw(tester, api);

    await _requestAmount(tester, '5');

    expect(api.posts, isEmpty);
    expect(find.text('Minimum withdrawal is GH₵10.00'), findsOneWidget);
  });

  testWidgets('a request above the balance never reaches the server', (tester) async {
    final api = _FakeApiClient();
    await _pumpWithdraw(tester, api);

    await _requestAmount(tester, '2000');

    expect(api.posts, isEmpty);
    expect(find.text('You can withdraw at most GH₵1,040.00'), findsOneWidget);
  });

  testWidgets('a missing MoMo number is caught before submitting', (tester) async {
    final api = _FakeApiClient();
    await _pumpWithdraw(tester, api);

    await tester.enterText(find.widgetWithText(TextField, '0539790093'), '');
    await _requestAmount(tester, '50');

    expect(api.posts, isEmpty);
    expect(find.text('Enter the MoMo number that should receive the money'), findsOneWidget);
  });

  testWidgets('the review sheet has to be confirmed before the money moves', (tester) async {
    final api = _FakeApiClient();
    await _pumpWithdraw(tester, api);

    await tester.enterText(find.widgetWithText(TextField, 'Amount (GH₵)'), '500');
    await _tapButton(tester, 'Review withdrawal');

    expect(find.text('Check your payout details'), findsOneWidget);
    expect(find.text('GH₵500.00'), findsOneWidget);
    expect(api.posts, isEmpty);

    await _tapButton(tester, 'Request withdrawal');

    // Still nothing sent: the PIN pad stands between the review and the money.
    expect(api.posts, isEmpty);

    await _enterPin(tester);

    expect(api.posts.length, 1);
    final (path, body) = api.posts.single;
    expect(path, '/wallet/withdraw');
    expect(body, {
      'amount': 500.0,
      'payout_type': 'momo',
      'momo_number': '0539790093',
      'account_name': 'Robert Asare',
      'network': 'mtn',
      'payment_pin': '1234',
    });
  });

  testWidgets('the chosen network is what gets sent', (tester) async {
    final api = _FakeApiClient();
    await _pumpWithdraw(tester, api);

    await tester.tap(find.text('Telecel Cash'));
    await tester.pumpAndSettle();
    await _requestAmount(tester, '50');
    await _tapButton(tester, 'Request withdrawal');
    await _enterPin(tester);

    expect(api.posts.single.$2['network'], 'telecel');
  });

  testWidgets('a request in flight still leaves the form open for another withdrawal', (tester) async {
    await _pumpWithdraw(
      tester,
      _FakeApiClient(overview: _overview(hasPending: true, items: [_paidRequest])),
    );

    expect(find.text('Withdrawal in processing'), findsOneWidget);
    expect(find.textContaining('You can submit another withdrawal'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Review withdrawal'), findsOneWidget);
    expect(find.text('Withdraw all'), findsOneWidget);
  });

  testWidgets('too small a balance explains itself instead of failing later', (tester) async {
    await _pumpWithdraw(tester, _FakeApiClient(overview: _overview(available: 4)));

    expect(find.text('Minimum withdrawal is GH₵10.00'), findsOneWidget);
    expect(find.textContaining('Your available balance is GH₵4.00'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Review withdrawal'), findsNothing);
  });

  testWidgets('past requests show their status and any rejection reason', (tester) async {
    await _pumpWithdraw(
      tester,
      _FakeApiClient(overview: _overview(items: [_rejectedRequest, _paidRequest])),
    );

    // The history sits under the form, so bring it into view first.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Withdrawal requests'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Paid out'), findsOneWidget);
    expect(find.text('GH₵75.00'), findsOneWidget);
    expect(find.text('GH₵300.00'), findsOneWidget);
    expect(find.text('Name did not match the MoMo account.'), findsOneWidget);
  });

  group('WithdrawalOverview', () {
    test('reads the summary the API sends', () {
      final overview = WithdrawalOverview.fromJson(_overview(items: [_paidRequest]));

      expect(overview.availableBalance, 1040);
      expect(overview.minimum, 10);
      expect(overview.hasPending, isFalse);
      expect(overview.canWithdraw, isTrue);
      expect(overview.items.single.statusLabel, 'Paid out');
      expect(overview.items.single.isPaid, isTrue);
    });

    test('blocks withdrawing only when the balance is short', () {
      expect(WithdrawalOverview.fromJson(_overview(hasPending: true)).canWithdraw, isTrue);
      expect(WithdrawalOverview.fromJson(_overview(available: 9.99)).canWithdraw, isFalse);
    });
  });
}
