import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/account/wallet_orders_screens.dart';
import 'package:cityshop_mobile/store/app_store.dart';
import 'package:cityshop_mobile/widgets/common_widgets.dart';

Map<String, dynamic> _order({String? logo}) => {
      'id': 1,
      'order_number': 'CS202607235B806A',
      'status': 'pending',
      'payment_status': 'pending',
      'payment_method': 'direct',
      'total': 20.0,
      'created_at': '2026-07-23T19:17:00+00:00',
      'receiver_name': 'Kofi amoah',
      'receiver_phone': '0539790093',
      'city': 'Sefwi Bekwai',
      'region': 'Western North',
      'seller': {
        'id': 5,
        'store_name': 'City Unlock',
        'store_slug': 'city-unlock',
        'store_logo': logo,
      },
      'items': [
        {
          'id': 11,
          'product_name': 'Tecno power switch',
          'quantity': 1,
          'unit_price': 20.0,
          'line_total': 20.0,
          'status': 'pending',
          'image_url': null,
        },
      ],
    };

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.orderJson);

  final Map<String, dynamic> orderJson;

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) async => Response(
        requestOptions: RequestOptions(path: path),
        data: path == '/orders/1' ? {'data': orderJson} : const <String, dynamic>{},
      );
}

/// The order screen's card trips Material's "ListTile inside a coloured
/// DecoratedBox" warning, and the test font is wide enough to overflow rows that
/// fit on a phone. Neither says anything about the avatar.
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

Future<void> _pumpOrder(WidgetTester tester, {String? logo}) async {
  _ignoreUnrelatedWarnings();
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final store = AppStore(_FakeApiClient(_order(logo: logo)))
    ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: const MaterialApp(home: OrderDetailScreen(orderId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('StoreAvatar', () {
    testWidgets('shows the shop photo when the store has one', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StoreAvatar(
            name: 'City Unlock',
            photo: 'https://cityunlock.net/storage/seller-documents/shop.jpg',
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'https://cityunlock.net/storage/seller-documents/shop.jpg');
      // The initial shows through only until the photo arrives.
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('resolves a relative path against the media host', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StoreAvatar(name: 'City Unlock', photo: 'storage/seller-documents/shop.jpg'),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, endsWith('/storage/seller-documents/shop.jpg'));
      expect(image.imageUrl, startsWith('http'));
    });

    testWidgets('falls back to the store initial without a photo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: StoreAvatar(name: 'City Unlock', photo: null)),
      );

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('an unnamed store still gets a placeholder letter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: StoreAvatar(name: '  ', photo: '')),
      );

      expect(find.text('S'), findsOneWidget);
    });
  });

  group('order detail seller row', () {
    testWidgets('renders the store logo from the order payload', (tester) async {
      await _pumpOrder(tester, logo: 'https://cityunlock.net/storage/seller-documents/shop.jpg');

      expect(find.text('Seller information'), findsOneWidget);

      final avatar = tester.widget<StoreAvatar>(find.byType(StoreAvatar));
      expect(avatar.photo, 'https://cityunlock.net/storage/seller-documents/shop.jpg');
      expect(avatar.name, 'City Unlock');
    });

    testWidgets('keeps the initial when the seller never uploaded a photo', (tester) async {
      await _pumpOrder(tester);

      expect(find.byType(StoreAvatar), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });
  });
}
