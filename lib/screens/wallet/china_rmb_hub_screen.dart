import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Buyer entry for China / RMB: Buy RMB (Transfer to China) and Sell RMB.
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
                              ? 'Buy RMB rate: not published'
                              : 'Buy / Transfer · 1 RMB = GH₵${buyGhsPerRmb.toStringAsFixed(4)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sellUsdPerRmb == null
                              ? 'Sell RMB rate: not published'
                              : 'Sell (we buy) · 1 RMB = \$${sellUsdPerRmb.toStringAsFixed(4)}'
                                  '${sellGhsPerUsd == null ? '' : ' · 1 USD = GH₵${sellGhsPerUsd.toStringAsFixed(2)}'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ServiceTile(
                    icon: Icons.south_west_rounded,
                    title: 'Buy RMB',
                    subtitle: 'Pay GHS · receive RMB on Alipay in China',
                    badge: buyConfig['enabled'] == true ? 'Open' : 'Paused',
                    open: buyConfig['enabled'] == true,
                    onTap: () => context.push('/wallet/china-transfer'),
                  ),
                  const SizedBox(height: 10),
                  _ServiceTile(
                    icon: Icons.north_east_rounded,
                    title: 'Sell RMB',
                    subtitle: 'Sell your RMB · receive USD or GHS',
                    badge: sellConfig['enabled'] == true ? 'Open' : 'Paused',
                    open: sellConfig['enabled'] == true,
                    onTap: () => context.push('/wallet/sell-rmb'),
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
                      title: Text('Buy · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
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
                      title: Text('Sell · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
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

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.open,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: open ? const Color(0xFFCCFBF1) : AppColors.border,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: open ? const Color(0xFF0F766E) : AppColors.textMuted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: open ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: open ? const Color(0xFF166534) : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
