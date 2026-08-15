import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/utils/wallet_statement_printer.dart';
import 'package:cityshop_mobile/widgets/common_widgets.dart';

List<WalletTransactionItem> _transactions() => [
      WalletTransactionItem.fromJson({
        'id': 3,
        'type': 'transfer_in',
        'type_label': 'Money Received',
        'amount': 5.0,
        // Em dash and cedi sign come straight from the backend and are outside
        // Latin-1, which the built-in PDF fonts cannot draw.
        'description': 'Transfer from Robert Asare — QR Code payment of GH₵5',
        'reference': 'TRF-4620B65988A5',
        'created_at': '2026-08-08T09:43:00+00:00',
        'balance_before': 2832.40,
        'balance_after': 2837.40,
      }),
      WalletTransactionItem.fromJson({
        'id': 2,
        'type': 'transfer_out',
        'type_label': 'Money Sent',
        'amount': -1.0,
        'description': 'Transfer to Robert Asare',
        'reference': 'TRF-EC27A7426FD9',
        'created_at': '2026-08-08T08:28:00+00:00',
        'balance_before': 2833.40,
        'balance_after': 2832.40,
      }),
      WalletTransactionItem.fromJson({
        'id': 1,
        'type': 'payout',
        'type_label': 'Payout Sent',
        'amount': -20.0,
        'description': 'Withdrawal to MoMo',
        'reference': 'WD-13',
        'created_at': '2026-08-07T16:02:00+00:00',
        'balance_before': 2853.40,
        'balance_after': 2833.40,
      }),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('statement renders with the branding logo', () async {
    final logoBytes = (await rootBundle.load(BrandMark.assetPath)).buffer.asUint8List();

    final doc = buildWalletStatementDocument(
      accountName: 'Robert Asare',
      accountMobile: '0244123456',
      transactions: _transactions(),
      periodLabel: 'Last 30 days',
      closingBalance: 2837.40,
      logo: pw.MemoryImage(logoBytes),
    );

    expect((await doc.save()).length, greaterThan(1000));
  });

  test('statement stays printable without a logo or balances', () async {
    final doc = buildWalletStatementDocument(
      accountName: 'Robert Asare',
      transactions: [
        WalletTransactionItem.fromJson({
          'id': 9,
          'type': 'top_up',
          'type_label': 'Top Up',
          'amount': 10.0,
          'description': '',
          'created_at': null,
        }),
      ],
      periodLabel: 'All transactions',
    );

    expect((await doc.save()).length, greaterThan(1000));
  });

  test('an empty period still produces a statement', () async {
    final doc = buildWalletStatementDocument(
      accountName: 'Robert Asare',
      transactions: const [],
      periodLabel: 'Last 30 days',
      closingBalance: 0,
    );

    expect((await doc.save()).length, greaterThan(1000));
  });
}
