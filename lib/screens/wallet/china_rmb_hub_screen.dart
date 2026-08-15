import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Buyer entry for China / RMB: GHS → RMB (buy) and RMB → GHS (sell).
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

  /// `buy` = GHS → RMB, `sell` = RMB → GHS (matches the Exchange Type cards).
  String selectedType = 'buy';

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

  void _openSelected() {
    if (selectedType == 'buy') {
      if (!buyOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GHS → RMB is paused right now')),
        );
        return;
      }
      context.push('/wallet/china-transfer');
      return;
    }
    if (!sellOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RMB → GHS is paused right now')),
      );
      return;
    }
    context.push('/wallet/sell-rmb');
  }

  @override
  Widget build(BuildContext context) {
    final buyGhsPerRmb = (buyRate?['ghs_per_rmb'] as num?)?.toDouble();
    final sellUsdPerRmb = (sellRate?['usd_per_rmb'] as num?)?.toDouble();
    final sellGhsPerUsd = (sellRate?['ghs_per_usd'] as num?)?.toDouble();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('China / RMB')),
      body: loading
          ? const FullPageLoader(label: 'Loading China / RMB…')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RMB Rates',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          buyGhsPerRmb == null
                              ? 'GHS → RMB: not published'
                              : 'GHS → RMB · 1 RMB = GH₵${buyGhsPerRmb.toStringAsFixed(4)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sellUsdPerRmb == null
                              ? 'RMB → GHS: not published'
                              : 'RMB → GHS · 1 RMB = \$${sellUsdPerRmb.toStringAsFixed(4)}'
                                  '${sellGhsPerUsd == null ? '' : ' · 1 USD = GH₵${sellGhsPerUsd.toStringAsFixed(2)}'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Exchange Type',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ExchangeTypeCard(
                          title: 'GHS → RMB',
                          subtitle: 'Ghana to China',
                          selected: selectedType == 'buy',
                          paused: !buyOpen,
                          onTap: () => setState(() => selectedType = 'buy'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ExchangeTypeCard(
                          title: 'RMB → GHS',
                          subtitle: 'China to Ghana',
                          selected: selectedType == 'sell',
                          paused: !sellOpen,
                          onTap: () => setState(() => selectedType = 'sell'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _openSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        selectedType == 'buy' ? 'Continue · Buy RMB' : 'Continue · Sell RMB',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text('Recent activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (buyTransfers.isEmpty && sellTransfers.isEmpty)
                    const Text('No China / RMB transactions yet.', style: TextStyle(color: Colors.black54)),
                  ...buyTransfers.take(5).map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFEDD5),
                        child: Icon(Icons.south_west_rounded, color: AppColors.accent, size: 18),
                      ),
                      title: Text('GHS → RMB · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        '¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} · ${item['status_label']}',
                      ),
                      onTap: () => context.push('/wallet/china-transfer/${item['id']}'),
                    );
                  }),
                  ...sellTransfers.take(5).map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    final currency = (quote['payout_currency'] as String?) ?? 'usd';
                    final payout = currency == 'ghs'
                        ? 'GH₵${((quote['ghs_payout'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'
                        : '\$${((quote['usd_payout'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFD1FAE5),
                        child: Icon(Icons.north_east_rounded, color: Color(0xFF047857), size: 18),
                      ),
                      title: Text('RMB → GHS · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        '¥${((quote['rmb_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} → $payout · ${item['status_label']}',
                      ),
                      onTap: () => context.push('/wallet/sell-rmb/${item['id']}'),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _ExchangeTypeCard extends StatelessWidget {
  const _ExchangeTypeCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.paused,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? const Color(0xFF059669) : const Color(0xFFD1D5DB);
    final titleColor = selected ? const Color(0xFF047857) : const Color(0xFF374151);
    final subtitleColor = selected ? const Color(0xFF10B981) : const Color(0xFF9CA3AF);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 2.5 : 1.2),
          ),
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subtitleColor,
                ),
              ),
              if (paused) ...[
                const SizedBox(height: 8),
                Text(
                  'Paused',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
