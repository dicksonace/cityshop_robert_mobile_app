import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// Buyer China / RMB: pay GHS at the live rate for Alipay, or sell RMB for MoMo.
/// Buyers do not hold an RMB wallet balance.
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

  /// buy | sell
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

  void _openSelected() {
    if (selectedType == 'buy') {
      if (!buyOpen) {
        _showPausedOnce('Transfers are paused right now');
        return;
      }
      context.push('/wallet/china-transfer/create');
      return;
    }
    if (!sellOpen) {
      _showPausedOnce('RMB → GHS is paused right now');
      return;
    }
    context.push('/wallet/sell-rmb');
  }

  void _showPausedOnce(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF115E59), Color(0xFF134E4A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Live rates',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          buyRmbPerGhs != null
                              ? 'Transfer · 1 GHS = ¥${buyRmbPerGhs.toStringAsFixed(3)}'
                              : 'Transfer rate: not published',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sellGhsPerRmb != null
                              ? 'Sell · 1 RMB = GH₵${sellGhsPerRmb.toStringAsFixed(4)}'
                              : 'Sell rate: not published',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Pay GHS and we send RMB to Alipay at this rate. No RMB balance is held in your wallet.',
                          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('What do you want to do?', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _ActionCard(
                    title: 'Transfer RMB to Alipay',
                    subtitle: 'Pay GHS · recipient gets RMB at today’s rate',
                    selected: selectedType == 'buy',
                    badge: buyOpen ? 'Live' : 'Paused',
                    badgeLive: buyOpen,
                    onTap: () => setState(() => selectedType = 'buy'),
                  ),
                  const SizedBox(height: 8),
                  _ActionCard(
                    title: 'Sell RMB → GHS',
                    subtitle: 'Send RMB to CityShop, get MoMo payout',
                    selected: selectedType == 'sell',
                    badge: sellOpen ? 'Live' : 'Paused',
                    badgeLive: sellOpen,
                    onTap: () => setState(() => selectedType = 'sell'),
                  ),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    label: selectedType == 'buy'
                        ? (buyOpen ? 'Continue · Transfer' : 'Transfers paused')
                        : (sellOpen ? 'Continue · Sell RMB' : 'Sell paused'),
                    onPressed: (selectedType == 'buy' && !buyOpen) || (selectedType == 'sell' && !sellOpen)
                        ? null
                        : _openSelected,
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
                        title: Text('Alipay · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w700)),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.badge,
    this.badgeLive = false,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final bool badgeLive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? Colors.teal : AppColors.border, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.teal.shade800 : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              if (badge != null) ...[
                const SizedBox(height: 6),
                Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: badgeLive ? Colors.teal : Colors.amber.shade800,
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
