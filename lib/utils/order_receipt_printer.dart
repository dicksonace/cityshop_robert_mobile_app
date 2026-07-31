import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

Future<void> printOrderReceipt(OrderModel order) async {
  final doc = pw.Document();
  final placed = _formatPlaced(order.createdAt);
  final address = [
    if ((order.digitalAddress ?? '').trim().isNotEmpty) order.digitalAddress!.trim(),
    if ((order.city ?? '').trim().isNotEmpty) order.city!.trim(),
    if ((order.region ?? '').trim().isNotEmpty) order.region!.trim(),
  ].join(', ');
  final notes = (order.deliveryNotes ?? '').trim();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text(
          'City Unlock',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Order receipt', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
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
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Deliver to', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),
              if ((order.receiverName ?? '').trim().isNotEmpty)
                pw.Text(order.receiverName!.trim(), style: const pw.TextStyle(fontSize: 11)),
              if ((order.receiverPhone ?? '').trim().isNotEmpty)
                pw.Text(order.receiverPhone!.trim(), style: const pw.TextStyle(fontSize: 11)),
              if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 11)),
              if (notes.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('Notes: $notes', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Payment: ${(order.paymentMethod ?? order.paymentChannel ?? '—').replaceAll('_', ' ')}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        if ((order.storeName ?? '').trim().isNotEmpty)
          pw.Text('Seller: ${order.storeName}', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.Text('Items', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _cell('Product', bold: true),
                _cell('Qty', bold: true, align: pw.TextAlign.center),
                _cell('Amount', bold: true, align: pw.TextAlign.right),
              ],
            ),
            for (final item in order.items)
              pw.TableRow(
                children: [
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

  await Printing.layoutPdf(
    name: 'CityUnlock-${order.orderNumber}',
    onLayout: (_) async => doc.save(),
  );
}

pw.Widget _badge(String label) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey200,
      borderRadius: pw.BorderRadius.circular(99),
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
