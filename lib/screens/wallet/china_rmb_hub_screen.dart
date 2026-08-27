import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// Buyer entry for China / RMB: convert, transfer Alipay, sell RMB.
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

  /// convert | buy | sell
  String selectedType = 'convert';

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
    if (selectedType == 'convert') {
      context.push('/wallet/convert');
      return;
    }
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
    final wallet = context.watch<AppStore>().wallet;
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
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('GHS wallet', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                                  Text(
                                    _ghs.format(wallet?.availableBalance ?? 0),
                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('RMB wallet', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                                  Text(
                                    '¥${(wallet?.rmbBalance ?? 0).toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          buyRmbPerGhs != null
                              ? 'Buy / convert · 1 GHS = ¥${buyRmbPerGhs.toStringAsFixed(3)}'
                              : 'GHS → RMB rate: not published',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sellGhsPerRmb != null
                              ? 'Sell / convert · 1 RMB = GH₵${sellGhsPerRmb.toStringAsFixed(4)}'
                              : 'RMB → GHS rate: not published',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('What do you want to do?', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _ActionCard(
                    title: 'Convert GHS ↔ RMB',
                    subtitle: 'Instant wallet exchange',
                    selected: selectedType == 'convert',
                    onTap: () => setState(() => selectedType = 'convert'),
                  ),
                  const SizedBox(height: 8),
                  _ActionCard(
                    title: 'Transfer RMB to Alipay',
                    subtitle: 'Send from RMB balance (or pay GHS externally)',
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
                    label: selectedType == 'convert'
                        ? 'Continue · Convert'
                        : selectedType == 'buy'
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
                    const Text('No China / RMB transactions yet.', style: TextStyle(color: AppColors.muted)),
                  ...buyTransfers.map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    final funding = item['funding_source']?.toString() ?? 'external';
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
                        tileColor: Colors.white,
                        title: Text(
                          'Alipay · ${item['reference']}${funding == 'rmb_wallet' ? ' · Wallet' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          funding == 'rmb_wallet'
                              ? '¥${rmb.toStringAsFixed(2)} from wallet'
                              : '${_ghs.format(total)} → ¥${rmb.toStringAsFixed(2)}',
                        ),
                        trailing: Text(
                          item['status_label']?.toString() ?? '',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ),
                    );
                  }),
                  ...sellTransfers.map((item) {
                    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : {};
                    final rmb = (quote['rmb_amount'] as num?)?.toDouble() ?? 0;
                    final ghs = (quote['ghs_payout'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => context.push('/wallet/sell-rmb/${item['id']}'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        tileColor: Colors.white,
                        title: Text('Sell · ${item['reference']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('¥${rmb.toStringAsFixed(2)} → ${_ghs.format(ghs)}'),
                        trailing: Text(
                          item['status_label']?.toString() ?? '',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.teal),
                        ),
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
    this.badgeLive = true,
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
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.teal.shade800 : AppColors.text)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
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
