import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/utils/order_receipt_printer.dart';
import 'package:cityshop_mobile/widgets/common_widgets.dart';

OrderModel _order() => OrderModel.fromJson({
      'id': 1,
      'order_number': 'CS20260731AB12CD',
      'status': 'delivered',
      'payment_status': 'paid',
      'payment_method': 'mobile_money',
      'receiver_name': 'Robert Asare',
      'receiver_phone': '0244123456',
      'region': 'Greater Accra',
      'city': 'Adenta',
      'digital_address': 'GA-492-1234',
      'delivery_notes': 'Call on arrival at the gate.',
      'subtotal': 150.0,
      'shipping_cost': 200.0,
      'total': 350.0,
      'created_at': '2026-07-31T09:12:00+00:00',
      'seller': {
        'id': 3,
        'store_name': 'Kofi Motors',
        'store_slug': 'kofi-motors',
        'seller_name': 'Kofi Mensah',
        'mobile': '0201112222',
        'whatsapp': '0203334444',
        'email': 'kofi@example.com',
        'business_address': 'Spintex Road',
        'city': 'Accra',
        'region': 'Greater Accra',
      },
      'items': [
        {
          'id': 11,
          'product_id': 20,
          'product_name': 'Electric bike',
          'quantity': 1,
          'unit_price': 150.0,
          'line_total': 150.0,
          'status': 'delivered',
          'image_url': 'https://cityunlock.net/storage/products/bike.jpg',
        },
        {
          'id': 12,
          'product_id': 21,
          'product_name': 'Spare battery pack',
          'quantity': 2,
          'unit_price': 50.0,
          'line_total': 100.0,
          'status': 'delivered',
          'image_url': null,
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receipt renders with the branding logo and product thumbnails', () async {
    final logoBytes = (await rootBundle.load(BrandMark.assetPath)).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);

    // Only the first item resolves, mirroring a product without a photo.
    final doc = buildOrderReceiptDocument(_order(), logo: logo, itemImages: {11: logo});

    expect((await doc.save()).length, greaterThan(1000));
  });

  test('receipt stays printable when no image resolves', () async {
    final doc = buildOrderReceiptDocument(_order());

    expect((await doc.save()).length, greaterThan(1000));
  });
}
