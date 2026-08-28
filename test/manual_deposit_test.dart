import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/manual_deposit_screen.dart';
import 'package:cityshop_mobile/store/app_store.dart';
import 'package:cityshop_mobile/widgets/momo_widgets.dart';

/// The shape `GET /api/v1/wallet/manual-funding` returns.
const _funding = {
  'enabled': true,
  'instructions': 'Send payment to one of the CityShop Mobile Money accounts below.',
  'paystack_configured': true,
  'accounts': [
    {
      'type': 'momo',
      'label': 'CityShop MTN',
      'account_name': 'CITY UNLOCK VENTURES / ROBERT ASARE',
      'account_number': '0539790093',
      'network': 'mtn',
      'bank_name': null,
    },
    {
      'type': 'momo',
      'label': 'CityShop Telecel',
      'account_name': 'CITY UNLOCK VENTURES',
      'account_number': '513014',
      'network': 'telecel',
      'bank_name': null,
    },
    {
      'type': 'momo',
      'label': 'CityShop AirtelTigo',
      'account_name': 'CITY UNLOCK VENTURES',
      'account_number': '0273706541',
      'network': 'airteltigo',
      'bank_name': null,
    },
  ],
  'requests': [
    {
      'id': 4,
      'amount': 250.0,
      'payment_reference': 'MP260731.1214.A12345',
      'status': 'pending',
      'admin_notes': null,
      'created_at': '2026-07-31T12:14:00+00:00',
      'reviewed_at': null,
    },
  ],
};

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.funding = _funding});

  final Map<String, dynamic> funding;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    int maxAttempts = 2,
  }) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      data: path == '/wallet/manual-funding' ? funding : const <String, dynamic>{},
    );
  }
}

Future<void> _pumpScreen(WidgetTester tester, ApiClient api) async {
  final store = AppStore(api)
    ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: const MaterialApp(home: ManualDepositScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _networkChip(String label) => find.descendant(
      of: find.byType(MomoNetworkPicker),
      matching: find.text(label),
    );

Future<void> _tapNetwork(WidgetTester tester, String label) async {
  await tester.tap(_networkChip(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lays out the two numbered steps and compact network picker', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    expect(find.text('1. Choose payment method'), findsOneWidget);
    expect(find.text('2. After you pay — submit proof'), findsOneWidget);

    expect(find.text('Pay with'), findsOneWidget);
    expect(find.byType(MomoNetworkPicker), findsOneWidget);
    expect(_networkChip('MTN'), findsNWidgets(2));
    expect(_networkChip('Telecel'), findsOneWidget);
    expect(_networkChip('AT'), findsNWidgets(2));

    // MTN is selected by default — pay-to details show inline.
    expect(find.text('PAY TO'), findsOneWidget);
    expect(find.text('0539790093'), findsOneWidget);

    expect(find.text('Amount sent (GH₵)'), findsOneWidget);
    expect(find.text("I've paid — submit for verification"), findsOneWidget);
  });

  testWidgets('switching networks updates inline pay-to details', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    expect(find.text('0539790093'), findsOneWidget);

    await _tapNetwork(tester, 'Telecel');

    expect(find.text('TILL NUMBER'), findsOneWidget);
    expect(find.text('MOMO NUMBER'), findsNothing);
    expect(find.text('513014'), findsOneWidget);
    expect(find.text('0539790093'), findsNothing);

    await _tapNetwork(tester, 'MTN');

    expect(find.text('0539790093'), findsOneWidget);
    expect(find.text('Send the exact amount, then fill the proof form below.'), findsOneWidget);
  });

  testWidgets('copy puts the number on the clipboard', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add('${(call.arguments as Map)['text']}');
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpScreen(tester, _FakeApiClient());

    await _tapNetwork(tester, 'AT');
    await tester.tap(find.text('COPY'));
    await tester.pump();

    expect(copied, ['0273706541']);
    expect(find.text('COPIED'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('COPY'), findsOneWidget);
  });

  testWidgets('submit is enabled when a network is auto-selected', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    expect(find.text('Choose a payment method above first.'), findsNothing);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text("I've paid — submit for verification"),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('an unconfigured network cannot be selected', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(
      tester,
      _FakeApiClient(funding: {
        ..._funding,
        'accounts': [(_funding['accounts'] as List).first],
      }),
    );

    expect(find.text('0539790093'), findsOneWidget);

    await _tapNetwork(tester, 'Telecel');

    expect(find.text('513014'), findsNothing);
    expect(find.text('0539790093'), findsOneWidget);
  });

  testWidgets('recent requests show amount and review status', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    final requests = find.text('Recent Deposit');
    await tester.scrollUntilVisible(requests, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('GH₵250.00'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);
    expect(find.textContaining('Ref: MP260731.1214.A12345'), findsOneWidget);
  });

  group('network helpers', () {
    test('free-text network names normalize to the three Ghana networks', () {
      expect(normalizeMomoNetworkId('MTN Mobile Money'), 'mtn');
      expect(normalizeMomoNetworkId('vodafone cash'), 'telecel');
      expect(normalizeMomoNetworkId('Airtel-Tigo'), 'airteltigo');
      expect(normalizeMomoNetworkId('  '), isNull);
      expect(normalizeMomoNetworkId('paypal'), isNull);
    });

    test('short numbers are tills even on MTN', () {
      expect(momoNumberFieldLabel('mtn', '0539790093'), 'MoMo number');
      expect(momoNumberFieldLabel('mtn', '513014'), 'Till number');
      expect(momoNumberFieldLabel('telecel', '0201234567'), 'Till number');
    });
  });
}
