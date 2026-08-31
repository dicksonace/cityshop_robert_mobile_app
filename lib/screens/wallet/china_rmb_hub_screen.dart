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

String _formatSellRate(double n) {
  if (n <= 0) return '—';
  return n.toStringAsFixed(4);
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

  bool _configLive(Map<String, dynamic> config) {
    if (config.containsKey('live')) return config['live'] == true;
    return config['enabled'] == true;
  }

  bool _configOpen(Map<String, dynamic> config) {
    if (config.containsKey('open')) return config['open'] == true;
    return config['enabled'] == true;
  }

  bool get buyLive => _configLive(buyConfig);
  bool get buyOpen => _configOpen(buyConfig);
  bool get sellLive => _configLive(sellConfig);
  bool get sellOpen => _configOpen(sellConfig);

  Map<String, dynamic>? get sellReadiness =>
      sellConfig['readiness'] is Map ? Map<String, dynamic>.from(sellConfig['readiness'] as Map) : null;

  String? get sellStatusMessage {
    final msg = sellConfig['status_message'] as String?;
    if (msg != null && msg.trim().isNotEmpty) return msg.trim();
    if (!sellLive) return 'Paused';
    final readiness = sellReadiness;
    if (readiness != null) {
      if (readiness['rate_published'] != true) return 'Rate not published';
      if (readiness['alipay_qr'] != true) return 'Alipay QR not ready';
    } else if (sellRate == null) {
      return 'Rate not published';
    } else if (!sellOpen) {
      return 'Not available yet';
    }
    return null;
  }

  Map<String, dynamic>? get buyTransferHours =>
      buyConfig['transfer_hours'] is Map ? Map<String, dynamic>.from(buyConfig['transfer_hours'] as Map) : null;

  String? get buyProcessingNote {
    if (buyInProcessingWindow) return null;
    return 'Transfer now will be processed tomorrow morning by 7:00 AM.';
  }

  bool get buyInProcessingWindow {
    final hours = buyTransferHours;
    if (hours == null || hours['configured'] != true) return true;
    return hours['in_processing_window'] != false;
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
                        if (buyOpen && buyRmbPerGhs != null && buyProcessingNote != null) ...[
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
                                    buyProcessingNote!,
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
                              !buyLive
                                  ? 'Buy RMB paused'
                                  : buyRate == null
                                      ? 'Rate not published'
                                      : 'Buy RMB →',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF047857), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF047857).withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SELL RMB',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sellGhsPerRmb != null
                              ? '1 RMB → GH₵${_formatSellRate(sellGhsPerRmb)}'
                              : 'Rate not published',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Send RMB via Alipay · get MoMo payout',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        if (sellStatusMessage != null) ...[
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
                                Icon(
                                  !sellLive ? Icons.pause_circle_outline : Icons.info_outline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    sellStatusMessage!,
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
                            onPressed: sellOpen && sellRate != null
                                ? () async {
                                    await context.push('/wallet/sell-rmb');
                                    if (mounted) _load(silent: true);
                                  }
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF047857),
                              disabledBackgroundColor: Colors.white.withValues(alpha: 0.55),
                              disabledForegroundColor: const Color(0xFF065F46),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              !sellLive
                                  ? 'Sell RMB paused'
                                  : sellRate == null
                                      ? 'Rate not published'
                                      : !sellOpen
                                          ? (sellStatusMessage ?? 'Not available yet')
                                          : 'Sell RMB →',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
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
