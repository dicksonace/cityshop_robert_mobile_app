import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../widgets/common_widgets.dart';

/// The built-in PDF fonts are Latin-1 only, so the statement stays within that
/// range: the cedi sign and em dashes render as tofu boxes on paper.
final _money = NumberFormat.currency(symbol: 'GHS ', decimalDigits: 2);
final _stamp = DateFormat('d MMM yyyy, h:mm a');

Future<void> printWalletStatement({
  required String accountName,
  String? accountMobile,
  required List<WalletTransactionItem> transactions,
  required String periodLabel,
  double? closingBalance,
}) async {
  final doc = buildWalletStatementDocument(
    accountName: accountName,
    accountMobile: accountMobile,
    transactions: transactions,
    periodLabel: periodLabel,
    closingBalance: closingBalance,
    logo: await _loadLogo(),
  );

  // layoutPdf gives the OS print sheet, which also offers "Save to Files" /
  // "Save as PDF" — so this covers both printing and downloading.
  await Printing.layoutPdf(
    name: 'CityShop-statement-${DateFormat('yyyyMMdd').format(DateTime.now())}',
    onLayout: (_) async => doc.save(),
  );
}

/// Built from already-resolved images so the layout can be rendered in tests
/// without touching the asset bundle or the network.
pw.Document buildWalletStatementDocument({
  required String accountName,
  String? accountMobile,
  required List<WalletTransactionItem> transactions,
  required String periodLabel,
  double? closingBalance,
  pw.ImageProvider? logo,
}) {
  final doc = pw.Document();

  var moneyIn = 0.0;
  var moneyOut = 0.0;
  for (final tx in transactions) {
    if (tx.amount >= 0) {
      moneyIn += tx.amount;
    } else {
      moneyOut += -tx.amount;
    }
  }

  final mobile = (accountMobile ?? '').trim();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Computer generated statement - no signature required.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'CityShop',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.orange800,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Wallet statement',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            if (logo != null)
              pw.SizedBox(
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
              child: _infoBox(
                title: 'Account holder',
                lines: [
                  _text(accountName),
                  if (mobile.isNotEmpty) 'Mobile: ${_text(mobile)}',
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _infoBox(
                title: 'Statement details',
                lines: [
                  'Period: ${_text(periodLabel)}',
                  'Generated: ${_stamp.format(DateTime.now())}',
                  'Entries: ${transactions.length}',
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            _summaryTile('Money in', _money.format(moneyIn), PdfColors.green800),
            pw.SizedBox(width: 8),
            _summaryTile('Money out', _money.format(moneyOut), PdfColors.red800),
            pw.SizedBox(width: 8),
            _summaryTile('Net', _money.format(moneyIn - moneyOut), PdfColors.grey800),
            if (closingBalance != null) ...[
              pw.SizedBox(width: 8),
              _summaryTile(
                'Closing balance',
                _money.format(closingBalance),
                PdfColors.orange800,
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 16),
        if (transactions.isEmpty)
          pw.Text(
            'No transactions in this period.',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          )
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(2.2),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.3),
              5: const pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('Date', bold: true),
                  _cell('Type', bold: true),
                  _cell('Details', bold: true),
                  _cell('Amount', bold: true, align: pw.TextAlign.right),
                  _cell('Before balance', bold: true, align: pw.TextAlign.right),
                  _cell('After balance', bold: true, align: pw.TextAlign.right),
                ],
              ),
              for (final tx in transactions)
                pw.TableRow(
                  children: [
                    _cell(_when(tx.createdAt)),
                    _cell(_text(tx.typeLabel)),
                    _cell(_details(tx)),
                    _cell(
                      '${tx.amount >= 0 ? '+' : '-'}${_money.format(tx.amount.abs())}',
                      align: pw.TextAlign.right,
                    ),
                    _cell(
                      tx.balanceBefore == null ? '-' : _money.format(tx.balanceBefore!),
                      align: pw.TextAlign.right,
                    ),
                    _cell(
                      tx.balanceAfter == null ? '-' : _money.format(tx.balanceAfter!),
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
            ],
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

String _details(WalletTransactionItem tx) {
  final reference = (tx.reference ?? '').trim();
  final description = tx.description.trim();
  return [
    if (description.isNotEmpty) _text(description),
    if (reference.isNotEmpty) 'Ref: ${_text(reference)}',
  ].join('\n');
}

String _when(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  try {
    return _stamp.format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

/// Keeps text inside Latin-1. Backend descriptions carry em dashes and cedi
/// signs, which the built-in PDF fonts cannot draw.
String _text(String raw) {
  final mapped = raw
      .replaceAll('\u2014', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201C', '"')
      .replaceAll('\u201D', '"')
      .replaceAll('\u2026', '...')
      .replaceAll('\u20B5', 'GHS');

  return String.fromCharCodes(
    mapped.runes.map((rune) => rune <= 0xFF ? rune : 0x3F),
  );
}

pw.Widget _summaryTile(String label, String value, PdfColor color) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      ),
    ),
  );
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
          pw.Text('-', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700))
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

pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}
