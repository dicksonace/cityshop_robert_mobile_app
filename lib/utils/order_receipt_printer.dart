import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api/api_config.dart';
import '../models/models.dart';
import '../widgets/common_widgets.dart';

/// The built-in PDF fonts are Latin-1 only, so the receipt sticks to ASCII:
/// the cedi sign and em dashes render as tofu boxes on paper.
final _money = NumberFormat.currency(symbol: 'GHS ', decimalDigits: 2);

const _empty = '-';

Future<void> printOrderReceipt(OrderModel order) async {
  final doc = buildOrderReceiptDocument(
    order,
    logo: await _loadLogo(),
    itemImages: await _loadItemImages(order.items),
  );

  await Printing.layoutPdf(
    name: 'CityUnlock-${order.orderNumber}',
    onLayout: (_) async => doc.save(),
  );
}

/// Builds the receipt document from already-resolved images so the layout can
/// be rendered in tests without touching the asset bundle or the network.
pw.Document buildOrderReceiptDocument(
  OrderModel order, {
  pw.ImageProvider? logo,
  Map<int, pw.ImageProvider> itemImages = const {},
}) {
  final doc = pw.Document();
  final placed = _formatPlaced(order.createdAt);
  final address = [
    if ((order.digitalAddress ?? '').trim().isNotEmpty) order.digitalAddress!.trim(),
    if ((order.city ?? '').trim().isNotEmpty) order.city!.trim(),
    if ((order.region ?? '').trim().isNotEmpty) order.region!.trim(),
  ].join(', ');
  final notes = (order.deliveryNotes ?? '').trim();

  final storeName = (order.storeName ?? '').trim();
  final sellerName = (order.sellerName ?? '').trim();
  final sellerMobile = (order.sellerMobile ?? '').trim();
  final sellerWhatsapp = (order.sellerWhatsapp ?? '').trim();
  final storeSlug = (order.storeSlug ?? '').trim();

  final sellerLines = <String>[
    if (storeName.isNotEmpty) storeName,
    if (sellerName.isNotEmpty && sellerName != storeName) 'Seller: $sellerName',
    if (sellerMobile.isNotEmpty) 'Tel: $sellerMobile',
    if (sellerWhatsapp.isNotEmpty && sellerWhatsapp != sellerMobile)
      'WhatsApp: $sellerWhatsapp',
    if ((order.sellerEmail ?? '').trim().isNotEmpty) 'Email: ${order.sellerEmail!.trim()}',
    if ((order.sellerAddress ?? '').trim().isNotEmpty) order.sellerAddress!.trim(),
    if (storeSlug.isNotEmpty) ApiConfig.storeShareUrl(storeSlug).replaceFirst('https://', ''),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'City Unlock',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.orange800,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Order receipt',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            if (logo != null)
              pw.Container(
                height: 64,
                width: 64,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(order.orderNumber, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Placed on $placed', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _badge((order.paymentStatus ?? 'pending').toUpperCase()),
                pw.SizedBox(height: 4),
                _badge(_pretty(order.status)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _infoBox(
                title: 'Seller information',
                lines: sellerLines.isEmpty ? [_empty] : sellerLines,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _infoBox(
                title: 'Deliver to',
                lines: [
                  if ((order.receiverName ?? '').trim().isNotEmpty) order.receiverName!.trim(),
                  if ((order.receiverPhone ?? '').trim().isNotEmpty) order.receiverPhone!.trim(),
                  if (address.isNotEmpty) address,
                  if (notes.isNotEmpty) 'Notes: $notes',
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Payment: ${(order.paymentMethod ?? order.paymentChannel ?? _empty).replaceAll('_', ' ')}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Items', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FixedColumnWidth(64),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _cell('', bold: true),
                _cell('Product', bold: true),
                _cell('Qty', bold: true, align: pw.TextAlign.center),
                _cell('Amount', bold: true, align: pw.TextAlign.right),
              ],
            ),
            for (final item in order.items)
              pw.TableRow(
                children: [
                  _imageCell(itemImages[item.id]),
                  _cell('${item.productName}\n${_pretty(item.status ?? order.status)}'),
                  _cell('${item.quantity}', align: pw.TextAlign.center),
                  _cell(_money.format(item.displayTotal), align: pw.TextAlign.right),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                _totalRow('Subtotal', _money.format(order.subtotal)),
                _totalRow('Shipping', _money.format(order.shippingCost)),
                pw.Divider(),
                _totalRow('Total', _money.format(order.total), bold: true),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Thank you for shopping with City Unlock.',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  return doc;
}

Future<pw.MemoryImage?> _loadLogo() async {
  try {
    final data = await rootBundle.load(BrandMark.assetPath);
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// Product thumbnails, keyed by order item id. A slow or broken image must not
/// block the receipt, so failures fall back to a placeholder cell.
Future<Map<int, pw.ImageProvider>> _loadItemImages(List<OrderItemModel> items) async {
  final images = <int, pw.ImageProvider>{};

  await Future.wait(items.map((item) async {
    final url = item.imageUrl;
    if (url == null || url.trim().isEmpty) return;
    try {
      images[item.id] = await networkImage(url.trim())
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }));

  return images;
}

pw.Widget _infoBox({required String title, required List<String> lines}) {
  final content = lines.where((l) => l.trim().isNotEmpty).toList();

  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 6),
        if (content.isEmpty)
          pw.Text(_empty, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700))
        else
          for (final line in content)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
            ),
      ],
    ),
  );
}

pw.Widget _imageCell(pw.ImageProvider? image) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.SizedBox(
      height: 54,
      width: 54,
      child: image == null
          ? pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey300),
              ),
            )
          : pw.Image(image, fit: pw.BoxFit.cover),
    ),
  );
}

/// The corner radius must stay below half the badge height: dart_pdf does not
/// clamp it like Flutter does, and an oversized radius paints a starburst that
/// bleeds across the page.
pw.Widget _badge(String label) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey200,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(label.toUpperCase(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
  );
}

pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}

pw.Widget _totalRow(String label, String value, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      ],
    ),
  );
}

String _pretty(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Pending';
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

String _formatPlaced(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat('M/d/yyyy, h:mm:ss a').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}
