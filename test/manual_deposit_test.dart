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
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      data: path == '/wallet/manual-funding' ? funding : const <String, dynamic>{},
    );
  }
}

/// Choosing a network fills the page card and opens the sheet at the same time,
/// so sheet assertions have to say which copy of the details they mean.
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

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

void main() {
  testWidgets('lays out the two numbered steps and every network', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    expect(find.text('1. Choose payment method'), findsOneWidget);
    expect(find.text('2. After you pay — submit proof'), findsOneWidget);

    // Same wording and ordering as the web page.
    expect(find.text('MTN Mobile Money'), findsOneWidget);
    expect(find.text('Telecel Cash'), findsOneWidget);
    expect(find.text('AirtelTigo Cash'), findsOneWidget);
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.text('MOMO'), findsNWidgets(2));
    expect(find.text('Tap to view & copy'), findsNWidgets(3));

    expect(find.text('Amount sent (GH₵)'), findsOneWidget);
    expect(find.text("I've paid — submit for verification"), findsOneWidget);
  });

  testWidgets('picking MTN shows the pay-to details and keeps them on the page', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    await tester.tap(find.text('MTN Mobile Money'));
    await tester.pumpAndSettle();

    // The sheet mirrors the web dialog.
    expect(find.text('Copy the number, send from your phone, then submit proof on this page.'), findsOneWidget);
    expect(_inSheet(find.text('PAY TO')), findsOneWidget);
    expect(_inSheet(find.text('MOMO NUMBER')), findsOneWidget);
    expect(_inSheet(find.text('0539790093')), findsOneWidget);
    expect(_inSheet(find.text('CITY UNLOCK VENTURES')), findsOneWidget);
    expect(_inSheet(find.text('ROBERT ASARE')), findsOneWidget);
    expect(_inSheet(find.text('COPY')), findsOneWidget);

    await tester.tap(find.text("I've copied — continue"));
    await tester.pumpAndSettle();

    // Details stay visible inline once a network is chosen.
    expect(find.text('Paying via MTN Mobile Money'), findsOneWidget);
    expect(find.text('View details again'), findsOneWidget);
    expect(find.text('Send the exact amount, then fill the proof form below.'), findsOneWidget);
    expect(find.text('0539790093'), findsOneWidget);
  });

  testWidgets('Telecel is paid into a till, not a MoMo number', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    await tester.tap(find.text('Telecel Cash'));
    await tester.pumpAndSettle();

    expect(_inSheet(find.text('TILL NUMBER')), findsOneWidget);
    expect(find.text('MOMO NUMBER'), findsNothing);
    expect(_inSheet(find.text('513014')), findsOneWidget);
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

    await tester.tap(find.text('AirtelTigo Cash'));
    await tester.pumpAndSettle();
    await tester.tap(_inSheet(find.text('COPY')));
    await tester.pump();

    expect(copied, ['0273706541']);
    expect(_inSheet(find.text('COPIED')), findsOneWidget);

    // The button goes back to "Copy" on its own.
    await tester.pump(const Duration(seconds: 2));
    expect(_inSheet(find.text('COPY')), findsOneWidget);
  });

  testWidgets('submitting is blocked until a network is chosen', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    expect(find.text('Choose a payment method above first.'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text("I've paid — submit for verification"),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('MTN Mobile Money'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I've copied — continue"));
    await tester.pumpAndSettle();

    expect(find.text('Choose a payment method above first.'), findsNothing);
    final enabled = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text("I've paid — submit for verification"),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(enabled.onPressed, isNotNull);
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

    expect(find.text('Not configured'), findsNWidgets(2));

    await tester.tap(find.text('Telecel Cash'));
    await tester.pumpAndSettle();

    expect(find.text('PAY TO'), findsNothing);
  });

  testWidgets('recent requests show amount and review status', (tester) async {
    tester.view.physicalSize = const Size(1440, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester, _FakeApiClient());

    final requests = find.text('Your recent requests');
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
