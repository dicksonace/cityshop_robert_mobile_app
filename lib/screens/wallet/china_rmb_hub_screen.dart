import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// China / RMB entry: Buy RMB (pay GHS → Alipay) or Sell RMB. No convert / no hold.
class ChinaRmbHubScreen extends StatefulWidget {
  const ChinaRmbHubScreen({super.key});

  @override
  State<ChinaRmbHubScreen> createState() => _ChinaRmbHubScreenState();
}

class _ChinaRmbHubScreenState extends State<ChinaRmbHubScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> buyConfig = {};
  Map<String, dynamic> sellConfig = {};
  List<Map<String, dynamic>> buyTransfers = [];
  List<Map<String, dynamic>> sellTransfers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final store = context.read<AppStore>();
      await store.loadWallet();
      final buy = await store.loadChinaTransfers();
      final sell = await store.loadSellRmb();
      if (!mounted) return;
      setState(() {
        buyConfig = Map<String, dynamic>.from(buy['config'] as Map? ?? {});
        sellConfig = Map<String, dynamic>.from(sell['config'] as Map? ?? {});
        buyTransfers = (buy['transfers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        sellTransfers = (sell['transfers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Map<String, dynamic>? get buyRate =>
      buyConfig['rate'] is Map ? Map<String, dynamic>.from(buyConfig['rate'] as Map) : null;

  Map<String, dynamic>? get sellRate =>
      sellConfig['rate'] is Map ? Map<String, dynamic>.from(sellConfig['rate'] as Map) : null;

  bool get buyOpen => buyConfig['enabled'] == true;
  bool get sellOpen => sellConfig['enabled'] == true;

  @override
  Widget build(BuildContext context) {
    final buyGhsPerRmb = (buyRate?['ghs_per_rmb'] as num?)?.toDouble();
    final buyRmbPerGhs = (buyRate?['rmb_per_ghs'] as num?)?.toDouble() ??
        (buyGhsPerRmb != null && buyGhsPerRmb > 0 ? 1 / buyGhsPerRmb : null);
    final sellUsdPerRmb = (sellRate?['usd_per_rmb'] as num?)?.toDouble();
    final sellGhsPerUsd = (sellRate?['ghs_per_usd'] as num?)?.toDouble();
    final sellGhsPerRmb = (sellRate?['ghs_per_rmb'] as num?)?.toDouble() ??
        (sellUsdPerRmb != null && sellGhsPerUsd != null ? sellUsdPerRmb * sellGhsPerUsd : null);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('China / RMB')),
      body: loading
          ? const FullPageLoader(label: 'Loading China / RMB…')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BUY RMB',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          buyRmbPerGhs != null
                              ? '1 GHS = ¥${buyRmbPerGhs.toStringAsFixed(2)}'
                              : 'Rate not published',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'No hidden fees · Secure transactions',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: buyOpen && buyRate != null
                                ? () => context.push('/wallet/china-transfer')
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF3730A3),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              buyOpen ? 'Buy RMB →' : 'Buy RMB paused',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: sellOpen ? () => context.push('/wallet/sell-rmb') : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sell RMB → GHS', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                              sellGhsPerRmb != null
                                  ? '1 RMB = GH₵${sellGhsPerRmb.toStringAsFixed(4)}'
                                  : 'Send RMB to CityShop, get MoMo payout',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                            ),
                            if (!sellOpen) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Paused',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.amber.shade800),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Recent activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (buyTransfers.isEmpty && sellTransfers.isEmpty)
                    const Text('No China / RMB transactions yet.', style: TextStyle(color: AppColors.textMuted)),
                  ...buyTransfers.map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    final rmb = (quote['rmb_amount'] as num?)?.toDouble() ?? 0;
                    final total = (quote['total_payable_ghs'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => context.push('/wallet/china-transfer/${item['id']}'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        title: Text('Buy RMB · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${_ghs.format(total)} → ¥${rmb.toStringAsFixed(2)}'),
                        trailing: Text('${item['status_label'] ?? item['status']}', style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }),
                  ...sellTransfers.map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    final rmb = (quote['rmb_amount'] as num?)?.toDouble() ?? 0;
                    final payoutCurrency = quote['payout_currency']?.toString() ?? 'ghs';
                    final payout = payoutCurrency == 'ghs'
                        ? _ghs.format((quote['ghs_payout'] as num?)?.toDouble() ?? 0)
                        : '\$${((quote['usd_payout'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => context.push('/wallet/sell-rmb/${item['id']}'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        title: Text('Sell · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('¥${rmb.toStringAsFixed(2)} → $payout'),
                        trailing: Text('${item['status_label'] ?? item['status']}', style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
