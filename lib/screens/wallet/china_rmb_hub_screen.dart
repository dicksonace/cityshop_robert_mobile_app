import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'china_transfer_screens.dart';

String _formatBuyRate(double n) {
  if (n <= 0) return '—';
  return n.toStringAsFixed(3);
}

void _popToWallet(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/shop?tab=wallet');
  }
}

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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
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
        error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) error = e.toString();
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

  Map<String, dynamic>? get buyTransferHours =>
      buyConfig['transfer_hours'] is Map ? Map<String, dynamic>.from(buyConfig['transfer_hours'] as Map) : null;

  bool get buyHoursOpen {
    final hours = buyTransferHours;
    if (hours == null || hours['configured'] != true) return true;
    return hours['is_open_now'] == true;
  }

  String get buyClosedNote {
    final hours = buyTransferHours;
    final fromApi = (hours?['closed_message'] as String?)?.trim();
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;
    final openLabel = hours?['open_time_label'] as String?;
    if (openLabel != null && openLabel.isNotEmpty) {
      return "Sorry, we're closed. We continue at $openLabel.";
    }
    return "Sorry, we're closed. We continue when we reopen.";
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popToWallet(context);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to wallet',
          onPressed: () => _popToWallet(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('China / RMB'),
        actions: [
          if (!loading)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text('Auto refresh', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _load(),
          ),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading China / RMB…')
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                              ? '1 GHS → ¥${_formatBuyRate(buyRmbPerGhs)} RMB'
                              : 'Rate not published',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'No hidden fees · Secure transactions',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        if (buyOpen && buyRmbPerGhs != null && !buyHoursOpen) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    buyClosedNote,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: buyOpen && buyRate != null
                                ? () async {
                                    await context.push('/wallet/china-transfer');
                                    if (mounted) _load(silent: true);
                                  }
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF3730A3),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              !buyOpen
                                  ? 'Buy RMB paused'
                                  : !buyHoursOpen
                                      ? 'Closed · opens ${buyTransferHours?['open_time_label'] ?? 'soon'}'
                                      : 'Buy RMB →',
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
                      onTap: sellOpen
                          ? () async {
                              await context.push('/wallet/sell-rmb');
                              if (mounted) _load(silent: true);
                            }
                          : null,
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
                  BuyRmbRecentTransfersSection(
                    title: 'Recent activity',
                    showAutoRefresh: true,
                    transfers: [
                      ...buyTransfers,
                      ...sellTransfers.map((item) => {
                            ...item,
                            'reference': 'Sell · ${item['reference']}',
                          }),
                    ],
                    sellFlowFor: (item) => sellTransfers.any((s) => s['id'] == item['id']),
                    onTransferTap: (item) async {
                      if (sellTransfers.any((s) => s['id'] == item['id'])) {
                        await context.push('/wallet/sell-rmb/${item['id']}');
                      } else {
                        await context.push('/wallet/china-transfer/${item['id']}');
                      }
                      if (mounted) _load(silent: true);
                    },
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
