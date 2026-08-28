import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/order_receipt_printer.dart';
import '../../utils/wallet_statement_printer.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/momo_widgets.dart';
import '../../widgets/tab_refresh.dart';
import '../../widgets/wallet_receipt_sheet.dart';
import '../cart/paystack_payment_screen.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

Map<String, double> _paystackRechargeQuote(double credit, {double percent = 1.95, double flat = 0}) {
  final amount = credit <= 0 ? 0.0 : credit;
  final rate = percent / 100;
  final charge = amount <= 0
      ? 0.0
      : rate >= 1
          ? amount + flat
          : (amount + flat) / (1 - rate);
  final chargeR = (charge * 100).round() / 100;
  final creditR = (amount * 100).round() / 100;
  return {
    'credit': creditR,
    'fee': ((chargeR - creditR) * 100).round() / 100,
    'charge': chargeR,
  };
}

enum _StatementPeriod {
  last30Days('Last 30 days', 30),
  last3Months('Last 3 months', 90),
  last12Months('Last 12 months', 365),
  everything('All transactions', null);

  const _StatementPeriod(this.label, this._days);

  final String label;
  final int? _days;

  DateTime? get since {
    final days = _days;
    if (days == null) return null;
    return DateTime.now().subtract(Duration(days: days));
  }
}

class WalletTab extends StatefulWidget {
  const WalletTab({super.key, this.shellTabIndex = 1});

  /// Bottom-nav slot this tab lives in. Buyer shop shell is 1; seller hub is 3.
  final int shellTabIndex;

  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> with AutoRefreshTab {
  bool loading = true;
  String? error;
  Map<String, dynamic>? funding;

  List<WalletTransactionItem> transactions = [];
  int transactionsPage = 0;
  int transactionsLastPage = 1;
  bool loadingMore = false;
  String? transactionsError;
  bool buildingStatement = false;
  String currencyFilter = 'all'; // all | GHS | RMB

  @override
  int? get tabIndex => widget.shellTabIndex;

  @override
  Future<void> refreshTabData({required bool background}) => _load(background: background);

  Future<void> _load({bool background = false}) async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (!background) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await store.loadWallet();
      final funds = await store.loadManualFunding();
      if (!mounted) return;
      funding = funds;
      error = null;
      await _loadTransactions(reset: true, background: background);
    } on ApiException catch (e) {
      if (!background || store.wallet == null) {
        error = e.message;
      }
    } catch (e) {
      if (!background || store.wallet == null) {
        error = e.toString();
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadTransactions({bool reset = false, bool background = false}) async {
    if (loadingMore) return;
    final nextPage = reset ? 1 : transactionsPage + 1;
    if (!background) {
      setState(() {
        loadingMore = true;
        transactionsError = null;
      });
    }
    try {
      final page = await context.read<AppStore>().fetchWalletTransactions(
            page: nextPage,
            currency: currencyFilter,
          );
      if (!mounted) return;
      setState(() {
        transactions = reset ? page.items : [...transactions, ...page.items];
        transactionsPage = page.currentPage;
        transactionsLastPage = page.lastPage;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => transactionsError = e.message);
    } catch (e) {
      if (mounted) setState(() => transactionsError = e.toString());
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  /// Statements are assembled from the ledger API rather than the rows already
  /// on screen, so a period covers everything even if the user never tapped
  /// "Load more". Capped so a long history cannot spin forever.
  Future<List<WalletTransactionItem>> _collectForStatement(DateTime? since) async {
    const perPage = 50;
    const maxPages = 20;
    final store = context.read<AppStore>();
    final collected = <WalletTransactionItem>[];

    var page = 1;
    var lastPage = 1;
    while (page <= lastPage && page <= maxPages) {
      final result = await store.fetchWalletTransactions(page: page, perPage: perPage);
      lastPage = result.lastPage;

      // Newest first, so the first row older than the cut-off ends the walk.
      var reachedCutOff = false;
      for (final tx in result.items) {
        final at = _txDate(tx);
        if (since != null && at != null && at.isBefore(since)) {
          reachedCutOff = true;
          break;
        }
        collected.add(tx);
      }
      if (reachedCutOff) break;
      page += 1;
    }

    return collected;
  }

  static DateTime? _txDate(WalletTransactionItem tx) {
    final raw = tx.createdAt;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> _openStatement() async {
    final choice = await showAppSheet<_StatementPeriod>(
      context: context,
      builder: (ctx) => SheetShell(
        children: [
          const Text(
            'Transaction statement',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a period. You can print it or save it as a PDF.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          for (final period in _StatementPeriod.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(period.label),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
              onTap: () => Navigator.of(ctx).pop(period),
            ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    setState(() => buildingStatement = true);
    try {
      final rows = await _collectForStatement(choice.since);
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transactions in that period')),
        );
        return;
      }
      final store = context.read<AppStore>();
      await printWalletStatement(
        accountName: store.user?.name ?? 'CityShop wallet',
        accountMobile: store.user?.mobile,
        transactions: rows,
        periodLabel: choice.label,
        closingBalance: store.wallet?.availableBalance,
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not build the statement. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => buildingStatement = false);
    }
  }

  Future<bool> _ensureKycToStoreFunds() async {
    final store = context.read<AppStore>();
    try {
      await store.loadKyc();
    } on ApiException catch (_) {}
    if (!mounted) return false;
    if (store.user?.canStoreWalletFunds == true) return true;
    final kyc = store.user?.kyc ?? const KycInfo();
    await showAppSheet<void>(
      context: context,
      builder: (ctx) => SheetShell(
        action: FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            context.push('/kyc');
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          child: Text(kyc.isPending ? 'View verification' : 'Verify Ghana Card', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        children: [
          Text(kyc.statusLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 8),
          Text(
            kyc.isPending
                ? 'The system is reviewing your Ghana Card. You can still buy items with Paystack.'
                : 'The system must approve your Ghana Card before you can transact with the CityShop wallet.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if ((kyc.adminNotes ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(kyc.adminNotes!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
    return false;
  }

  Future<void> _openRecharge({
    required bool paystackConfigured,
    required bool manualEnabled,
  }) async {
    if (!paystackConfigured && !manualEnabled) return;
    if (!await _ensureKycToStoreFunds()) return;

    // Only one path available — skip the chooser.
    if (paystackConfigured && !manualEnabled) {
      await _paystackTopUp();
      return;
    }
    if (!paystackConfigured && manualEnabled) {
      await _openManualRechargePreview();
      return;
    }

    final choice = await showAppSheet<String>(
      context: context,
      builder: (ctx) {
        return SheetShell(
          children: [
            const Text(
              'Recharge',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose how you want to add funds.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            Material(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(ctx, 'paystack'),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDBA74)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.smartphone, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Auto Paystack', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            SizedBox(height: 2),
                            Text(
                              'Instant MoMo or card',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(ctx, 'manual'),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.upload_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Manual', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            SizedBox(height: 2),
                            Text(
                              'MoMo / bank + upload proof',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;
    if (choice == 'manual') {
      await _openManualRechargePreview();
    } else if (choice == 'paystack') {
      await _paystackTopUp();
    }
  }

  Future<void> _paystackTopUp() async {
    final amountCtrl = TextEditingController();
    String method = 'momo';
    var submitting = false;
    final wallet = context.read<AppStore>().wallet;
    final feePercent = wallet?.paystackFeePercent ?? 1.95;
    final feeFlat = wallet?.paystackFeeFlat ?? 0;

    final started = await showAppSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final typed = double.tryParse(amountCtrl.text.trim()) ?? 0;
            final quote = _paystackRechargeQuote(typed, percent: feePercent, flat: feeFlat);
            return SheetShell(
              action: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: submitting
                      ? null
                      : () async {
                          final amount = double.tryParse(amountCtrl.text.trim());
                          if (amount == null || amount < 5) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Enter at least GHS 5')),
                            );
                            return;
                          }
                          setModal(() => submitting = true);
                          try {
                            final pay = await context.read<AppStore>().initializeWalletPaystack(
                                  amount: amount,
                                  method: method,
                                );
                            if (ctx.mounted) Navigator.pop(ctx, pay);
                          } on ApiException catch (e) {
                            setModal(() => submitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                            }
                          } catch (e) {
                            setModal(() => submitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          }
                        },
                  child: Text(
                    submitting
                        ? 'Starting…'
                        : quote['credit']! >= 5
                            ? 'Pay ${_money.format(quote['charge'])}'
                            : 'Recharge',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              children: [
                const Text(
                  'Recharge',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Top up via Paystack (MoMo or card).',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setModal(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Amount (GHS)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'momo', child: Text('Mobile Money')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                  ],
                  onChanged: submitting
                      ? null
                      : (v) {
                          if (v != null) setModal(() => method = v);
                        },
                ),
                if (quote['credit']! >= 5) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _FeeRow(label: 'Wallet credit', value: _money.format(quote['credit'])),
                        const Divider(height: 16),
                        _FeeRow(
                          label: 'You pay',
                          value: _money.format(quote['charge']),
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );

    amountCtrl.dispose();
    if (started == null || !mounted) return;

    final url = started['authorization_url'] as String?;
    final reference = started['reference'] as String? ?? '';
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start Paystack payment')),
      );
      return;
    }

    final store = context.read<AppStore>();
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PaystackPaymentScreen(
          authorizationUrl: url,
          reference: reference,
          onVerify: (ref) async {
            await store.verifyWalletPaystack(ref);
          },
        ),
      ),
    );

    if (!mounted) return;
    if (paid == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Funds added to your wallet')),
      );
    }
    // Reload either way: Paystack's webhook may have credited the top-up even
    // when the in-app verification did not run.
    await _load();
  }

  /// MoMo accounts keyed mtn|telecel|airteltigo from cached manual funding.
  Map<String, Map> _momoByNetworkFromFunding() {
    final map = <String, Map>{};
    final accounts = funding?['accounts'];
    if (accounts is! List) return map;
    for (final raw in accounts) {
      if (raw is! Map) continue;
      if (raw['type'] == 'bank') continue;
      final id = normalizeMomoNetworkId('${raw['network'] ?? ''}');
      if (id != null && !map.containsKey(id)) map[id] = raw;
    }
    return map;
  }

  String _fundingNumber(Map account) => '${account['account_number'] ?? account['number'] ?? ''}';

  String _fundingName(Map account) => '${account['account_name'] ?? account['name'] ?? ''}';

  /// Compact MoMo picker + pay-to details, then full manual deposit for proof.
  Future<void> _openManualRechargePreview() async {
    if (!await _ensureKycToStoreFunds()) return;
    if (!mounted) return;

    final momo = _momoByNetworkFromFunding();
    if (momo.isEmpty) {
      await _openManualDeposit();
      return;
    }

    String? selected;
    for (final id in ['mtn', 'telecel', 'airteltigo']) {
      if (momo.containsKey(id)) {
        selected = id;
        break;
      }
    }

    final continued = await showAppSheet<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final account = selected != null ? momo[selected] : null;
            return SheetShell(
              action: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: selected == null ? null : () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Continue — submit proof',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              children: [
                const Text(
                  'Manual deposit',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                ),
                const SizedBox(height: 16),
                if (account != null && selected != null) ...[
                  MomoNetworkPicker(
                    value: selected,
                    enabledNetworks: momo.keys.toSet(),
                    onChanged: (id) {
                      if (!momo.containsKey(id)) return;
                      setModal(() => selected = id);
                    },
                    selectedOnly: true,
                  ),
                  const SizedBox(height: 12),
                  PaymentDetailsCard(
                    accountNumber: _fundingNumber(account),
                    accountName: _fundingName(account),
                    network: selected,
                  ),
                ],
              ],
            );
          },
        );
      },
    );

    if (!mounted || continued != true) return;
    await context.push('/wallet/manual-deposit', extra: selected);
    if (mounted) await _load();
  }

  /// Manual deposit lives on its own page, mirroring the web flow.
  Future<void> _openManualDeposit() async {
    if (!await _ensureKycToStoreFunds()) return;
    await context.push('/wallet/manual-deposit');
    if (mounted) await _load();
  }

  Future<void> _openWithdraw() async {
    final done = await context.push<bool>('/wallet/withdraw');
    if (!mounted) return;
    if (done == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Withdrawal requested. Usually processed within 15 minutes and sometimes instant.'),
        ),
      );
    }
    await _load();
    _loadTransactions(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.isLoggedIn) {
      if (tabIsWarmingUp) return const FullPageLoader(label: 'Loading wallet…');
      return _Guest(onLogin: () => context.push('/login'));
    }
    if (loading && store.wallet == null) {
      return const FullPageLoader(label: 'Loading wallet…');
    }
    if (error != null && store.wallet == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            TextButton(onPressed: refreshNow, child: const Text('Retry')),
          ],
        ),
      );
    }

    final wallet = store.wallet;
    final enabled = funding?['enabled'] == true || wallet?.manualTopUpEnabled == true;
    final paystackConfigured =
        wallet?.paystackConfigured == true || funding?['paystack_configured'] == true;

    return RefreshIndicator(
      onRefresh: refreshNow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
                            child: Stack(
              children: [
                Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available balance', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  _money.format(wallet?.availableBalance ?? 0),
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Pending: ${_money.format(wallet?.pendingBalance ?? 0)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _WalletActionPair(
                  onWithdraw: _openWithdraw,
                  onRecharge: (paystackConfigured || enabled)
                      ? () => _openRecharge(
                            paystackConfigured: paystackConfigured,
                            manualEnabled: enabled,
                          )
                      : null,
                ),
              ],
            ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => context.push('/wallet/china-rmb'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'China / RMB',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!paystackConfigured && !enabled) ...[
            const SizedBox(height: 10),
            const Text(
              'Recharge is unavailable right now.',
              style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
            ),
          ],
          if (store.isSeller) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _WalletQrAction(
                    icon: Icons.qr_code_2_rounded,
                    label: 'My QR',
                    subtitle: 'Receive payments',
                    onTap: () => context.push('/qr/receive'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WalletQrAction(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan',
                    subtitle: 'Pay someone',
                    onTap: () => context.push('/qr/scan'),
                  ),
                ),
              ],
            ),
          ],
          if (!(store.user?.canStoreWalletFunds ?? false)) ...[
            const SizedBox(height: 10),
            Material(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: const Icon(Icons.badge_outlined, color: AppColors.accent),
                title: Text(
                  store.user?.kyc.statusLabel ?? 'Not verified',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('The system must approve your Ghana Card before you can transact with the CityShop wallet.'),
                trailing: const Text('ACTIVATE', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 12)),
                onTap: () => context.push('/kyc'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Transaction History',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    if (transactions.isNotEmpty)
                      TextButton.icon(
                        onPressed: buildingStatement ? null : _openStatement,
                        icon: buildingStatement
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 18),
                        label: Text(buildingStatement ? 'Preparing…' : 'Statement'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in const ['all', 'GHS'])
                      ChoiceChip(
                        label: Text(c == 'all' ? 'All' : c),
                        selected: currencyFilter == c,
                        onSelected: (_) {
                          if (currencyFilter == c) return;
                          setState(() => currencyFilter = c);
                          _loadTransactions(reset: true);
                        },
                      ),
                  ],
                ),
                if (transactionsError != null) ...[
                  const SizedBox(height: 10),
                  Text(transactionsError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  TextButton(
                    onPressed: () => _loadTransactions(reset: true),
                    child: const Text('Retry'),
                  ),
                ] else if (transactions.isEmpty && !loadingMore) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'No transactions yet.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ] else ...[
                  for (final tx in transactions) _WalletTransactionRow(tx: tx),
                  if (transactionsPage < transactionsLastPage)
                    TextButton(
                      onPressed: loadingMore ? null : () => _loadTransactions(),
                      child: Text(loadingMore ? 'Loading…' : 'Load more'),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletTransactionRow extends StatelessWidget {
  const _WalletTransactionRow({required this.tx});

  final WalletTransactionItem tx;

  static final _stamp = DateFormat('d MMM yyyy, h:mm a');

  String get _when {
    final raw = tx.createdAt;
    if (raw == null || raw.isEmpty) return '';
    try {
      return _stamp.format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final credit = tx.isCredit;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showWalletReceiptSheet(context, tx: tx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TransactionAvatar(tx: tx),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                tx.typeLabel,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if ((tx.reference ?? '').isNotEmpty)
                              Text(
                                tx.reference!,
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                          ],
                        ),
                        if (tx.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            tx.description,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                        if (_when.isNotEmpty)
                          Text(_when, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tx.isRmb
                        ? '${credit ? '+' : ''}¥${tx.amount.abs().toStringAsFixed(2)}'
                        : '${credit ? '+' : ''}${_money.format(tx.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: credit ? const Color(0xFF16A34A) : AppColors.danger,
                    ),
                  ),
                ],
              ),
              if (tx.balanceBefore != null || tx.balanceAfter != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _BalanceCell(label: 'Before balance', value: tx.balanceBefore),
                      ),
                      Expanded(
                        child: _BalanceCell(
                          label: 'After balance',
                          value: tx.balanceAfter,
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'View receipt',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile photo for transfers; type icon for other ledger rows.
class _TransactionAvatar extends StatelessWidget {
  const _TransactionAvatar({required this.tx});

  final WalletTransactionItem tx;

  @override
  Widget build(BuildContext context) {
    final name = (tx.counterpartyName ?? '').trim();
    final avatar = ApiConfig.resolveMediaUrl(tx.counterpartyAvatar);
    final credit = tx.isCredit;
    final initial = name.isNotEmpty
        ? name.substring(0, 1).toUpperCase()
        : (credit ? '+' : '−');

    return CircleAvatar(
      radius: 22,
      backgroundColor: credit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
      backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
      child: avatar.isNotEmpty
          ? null
          : Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: name.isNotEmpty ? 16 : 18,
                color: credit ? const Color(0xFF16A34A) : AppColors.danger,
              ),
            ),
    );
  }
}

class _BalanceCell extends StatelessWidget {
  const _BalanceCell({required this.label, required this.value, this.alignEnd = false});

  final String label;
  final double? value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        Text(
          _money.format(value ?? 0),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Compact QR pay / receive shortcuts on the seller wallet tab.
class _WalletQrAction extends StatelessWidget {
  const _WalletQrAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.ringOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Side-by-side Withdrawal | Recharge actions on the balance card.
class _WalletActionPair extends StatelessWidget {
  const _WalletActionPair({
    required this.onWithdraw,
    required this.onRecharge,
  });

  final VoidCallback onWithdraw;
  final VoidCallback? onRecharge;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
                onTap: onWithdraw,
                child: const Center(
                  child: Text(
                    'Withdrawal',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: onRecharge == null ? Colors.grey.shade400 : AppColors.primary,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
                onTap: onRecharge,
                child: Center(
                  child: Text(
                    onRecharge == null ? 'Unavailable' : 'Recharge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrdersTab extends StatefulWidget {
  const OrdersTab({
    super.key,
    this.onOpenWallet,
    this.onOpenMessages,
  });

  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenMessages;

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> with AutoRefreshTab {
  bool loading = true;
  String? error;
  /// Fixed tab order matching web Manage orders (never randomized).
  String activeTab = 'all';

  static const _hubShortcuts = <({String key, String label, IconData icon})>[
    (key: 'unpaid', label: 'Unpaid', icon: Icons.account_balance_wallet_outlined),
    (key: 'processing', label: 'Processing', icon: Icons.autorenew),
    (key: 'delivery', label: 'Delivery', icon: Icons.local_shipping_outlined),
    (key: 'confirm', label: 'Confirm', icon: Icons.inventory_outlined),
    (key: 'completed', label: 'Completed', icon: Icons.check_circle_outline),
    (key: 'review', label: 'Review', icon: Icons.star_outline),
  ];

  static const _statusTabs = <({String key, String label})>[
    (key: 'all', label: 'All'),
    (key: 'unpaid', label: 'Unpaid'),
    (key: 'processing', label: 'Processing'),
    (key: 'delivery', label: 'Delivery'),
    (key: 'confirm', label: 'Confirm'),
    (key: 'completed', label: 'Completed'),
    (key: 'review', label: 'Review'),
    (key: 'cancelled', label: 'Cancelled'),
  ];

  /// The order list sits below the hub cards, so picking a tab has to bring it
  /// into view — otherwise the tap looks like it did nothing.
  final _listSection = GlobalKey();
  final _tabAnchors = {for (final tab in _statusTabs) tab.key: GlobalKey()};

  @override
  int? get tabIndex => 2;

  @override
  Future<void> refreshTabData({required bool background}) => _load(background: background);

  void _selectTab(String key) {
    setState(() => activeTab = key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tab = _tabAnchors[key]?.currentContext;
      if (tab != null) {
        Scrollable.ensureVisible(
          tab,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
      final section = _listSection.currentContext;
      if (section != null) {
        Scrollable.ensureVisible(
          section,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _load({bool background = false}) async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (!background) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await store.loadOrders();
      await store.refreshNotificationCounts();
      error = null;
    } on ApiException catch (e) {
      if (!background || store.orders.isEmpty) {
        error = e.message;
      }
    } catch (e) {
      if (!background || store.orders.isEmpty) {
        error = e.toString();
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _matchesTab(OrderModel order, String tab) {
    final status = (order.status ?? '').toLowerCase();
    final pay = (order.paymentStatus ?? '').toLowerCase();
    final method = (order.paymentMethod ?? '').toLowerCase();
    final itemStatuses = order.items.map((i) => (i.status ?? '').toLowerCase()).toList();

    switch (tab) {
      case 'all':
        return true;
      case 'unpaid':
        return status != 'cancelled' &&
            pay == 'pending' &&
            method != 'cash' &&
            !order.directPaymentUnderReview;
      case 'processing':
        return (pay == 'paid' || order.directPaymentUnderReview) &&
            const {'pending', 'processing', 'packed', 'call_confirmed'}.contains(status);
      case 'delivery':
        return status == 'shipped' || itemStatuses.contains('shipped');
      case 'confirm':
        return status == 'awaiting_confirmation' ||
            itemStatuses.contains('awaiting_confirmation');
      case 'completed':
        return status == 'delivered' && pay == 'paid';
      case 'review':
        return order.items.any((i) => i.canReview);
      case 'cancelled':
        return status == 'cancelled';
      default:
        return true;
    }
  }

  Map<String, int> _counts(List<OrderModel> orders) {
    final keys = ['all', 'unpaid', 'processing', 'delivery', 'confirm', 'completed', 'review', 'cancelled'];
    return {
      for (final key in keys)
        key: key == 'all' ? orders.length : orders.where((o) => _matchesTab(o, key)).length,
    };
  }

  String _headline(OrderModel order) {
    final status = (order.status ?? '').toLowerCase();
    final pay = (order.paymentStatus ?? '').toLowerCase();
    final method = (order.paymentMethod ?? '').toLowerCase();
    if (status == 'cancelled') return 'Processing';
    if (order.directPaymentRejected) return 'Payment declined';
    if (pay == 'pending' && method != 'cash' && !order.directPaymentUnderReview) {
      return 'Awaiting payment';
    }
    if (status == 'delivered') return 'Order completed';
    if (status == 'awaiting_confirmation') return 'Confirm delivery';
    if (status == 'shipped') return 'Out for delivery';
    if (status == 'packed') return 'Packing';
    if (status == 'processing' || status == 'pending') return 'Processing';
    return _pretty(status);
  }

  String _pretty(String raw) {
    if (raw.isEmpty) return 'Pending';
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _statusLine(OrderModel order) {
    final status = (order.status ?? '').toLowerCase();
    final pay = (order.paymentStatus ?? '').toLowerCase();
    final method = (order.paymentMethod ?? '').toLowerCase();
    if (status == 'cancelled') return 'Order cancelled';
    if (order.directPaymentRejected) {
      return 'Payment not confirmed · tap to send it again';
    }
    if (pay == 'pending' && method != 'cash' && !order.directPaymentUnderReview) {
      return 'Waiting for payment';
    }
    if (order.directPaymentUnderReview && (status == 'pending' || status == 'processing')) {
      return 'Payment sent · waiting for the seller to confirm';
    }
    if (status == 'shipped') return 'Out for delivery';
    if (status == 'awaiting_confirmation') {
      return 'Delivered — tap Confirm delivery when you receive your item';
    }
    if (status == 'delivered') return 'Order completed';
    if (status == 'packed') return 'Seller is packing your order';
    if (status == 'processing' || status == 'pending') {
      return method == 'cash'
          ? 'Cash on delivery · Seller is preparing your order'
          : 'Seller is preparing your order';
    }
    return 'Processing your order';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.isLoggedIn) {
      if (tabIsWarmingUp) return const FullPageLoader(label: 'Loading orders…');
      return _Guest(onLogin: () => context.push('/login'));
    }
    if (loading && store.orders.isEmpty) {
      return const FullPageLoader(label: 'Loading orders…');
    }
    if (error != null && store.orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            TextButton(onPressed: refreshNow, child: const Text('Retry')),
          ],
        ),
      );
    }

    final orders = store.orders;
    final counts = _counts(orders);
    final filtered = orders.where((o) => _matchesTab(o, activeTab)).toList();

    return RefreshIndicator(
      onRefresh: refreshNow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Manage orders',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        store.totalOrders > 0 ? 'My orders (${store.totalOrders})' : 'My orders',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _selectTab('all'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View all'),
                          Icon(Icons.chevron_right, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.15,
                  children: [
                    for (final item in _hubShortcuts)
                      _HubShortcut(
                        label: item.label,
                        icon: item.icon,
                        count: counts[item.key] ?? 0,
                        active: activeTab == item.key,
                        onTap: () => _selectTab(item.key),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Payments & account', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickLink(
                        icon: Icons.confirmation_number_outlined,
                        label: 'Coupon',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coupons open from checkout when available')),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _QuickLink(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Wallet',
                        onTap: widget.onOpenWallet,
                      ),
                    ),
                    Expanded(
                      child: _QuickLink(
                        icon: Icons.chat_bubble_outline,
                        label: 'Message',
                        onTap: widget.onOpenMessages,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: _listSection,
            color: Colors.white,
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final tab in _statusTabs) ...[
                          InkWell(
                            key: _tabAnchors[tab.key],
                            onTap: () => _selectTab(tab.key),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: activeTab == tab.key ? AppColors.accent : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                              child: Text(
                                (counts[tab.key] ?? 0) > 0 ? '${tab.label} (${counts[tab.key]})' : tab.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: activeTab == tab.key ? AppColors.accent : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 40, 24, 48),
                    child: Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No orders in this section', style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 6),
                        Text(
                          'Try another tab or start shopping.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                    child: Column(
                      children: [
                        for (final order in filtered) ...[
                          _ManageOrderCard(
                            order: order,
                            headline: _headline(order),
                            statusLine: _statusLine(order),
                            onOpen: () => context.push('/orders/${order.id}'),
                            onRefund: () => context.push('/orders/${order.id}?action=refund'),
                            onReview: () => context.push('/orders/${order.id}?action=review'),
                            onBuyAgain: () {
                              final match = order.items.where(
                                (i) => (i.productSlug ?? '').isNotEmpty,
                              );
                              final slug = match.isEmpty ? null : match.first.productSlug;
                              if (slug != null) {
                                context.push('/products/$slug');
                              } else {
                                context.push('/orders/${order.id}');
                              }
                            },
                            onVisitStore: order.storeSlug == null || order.storeSlug!.isEmpty
                                ? null
                                : () => context.push('/stores/${order.storeSlug}'),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HubShortcut extends StatelessWidget {
  const _HubShortcut({
    required this.label,
    required this.icon,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: active ? AppColors.ringOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: active ? AppColors.primary : AppColors.textSecondary, size: 26),
                if (count > 0)
                  Positioned(
                    right: -10,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ManageOrderCard extends StatelessWidget {
  const _ManageOrderCard({
    required this.order,
    required this.headline,
    required this.statusLine,
    required this.onOpen,
    this.onRefund,
    this.onReview,
    this.onBuyAgain,
    this.onVisitStore,
  });

  final OrderModel order;
  final String headline;
  final String statusLine;
  final VoidCallback onOpen;
  final VoidCallback? onRefund;
  final VoidCallback? onReview;
  final VoidCallback? onBuyAgain;
  final VoidCallback? onVisitStore;

  @override
  Widget build(BuildContext context) {
    final first = order.items.isNotEmpty ? order.items.first : null;
    final imageUrl = first?.imageUrl;
    final paid = (order.paymentStatus ?? '').toLowerCase() == 'paid';
    final cancelled = (order.status ?? '').toLowerCase() == 'cancelled';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order.storeName ?? 'Seller',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    if (onVisitStore != null)
                      TextButton(
                        onPressed: onVisitStore,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.primary,
                        ),
                        child: const Text('Visit'),
                      ),
                    Text(
                      headline,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: AppColors.background,
                        child: imageUrl == null || imageUrl.isEmpty
                            ? const Icon(Icons.image_outlined, color: AppColors.textMuted)
                            : CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            first?.productName ?? 'Order items',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                          if (paid && !cancelled) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Buyer protection · Secured payment',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.emerald),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.ringOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(
                  order.orderNumber,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    const Spacer(),
                    const Text('Total ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                      _money.format(order.total),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (order.canRequestRefund ||
                        order.items.any((i) => i.canRequestRefund))
                      OutlinedButton(
                        onPressed: onRefund ?? onOpen,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Apply for refund'),
                      ),
                    OutlinedButton(
                      onPressed: onBuyAgain ?? onOpen,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Buy again'),
                    ),
                    if (order.items.any((i) => i.canReview))
                      FilledButton(
                        onPressed: onReview ?? onOpen,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Write review'),
                      )
                    else
                      OutlinedButton(
                        onPressed: onOpen,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('View details'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.initialAction});
  final int orderId;
  final String? initialAction;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool loading = true;
  String? error;
  OrderModel? order;
  bool _handledInitialAction = false;

  static const _paidSteps = <String>[
    'Processing',
    'Packing',
    'Out for delivery',
    'Delivered',
    'Completed',
  ];

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
      order = await context.read<AppStore>().fetchOrder(widget.orderId);
      if (!_handledInitialAction) {
        _handledInitialAction = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _runInitialAction();
        });
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _runInitialAction() {
    final o = order;
    if (o == null) return;
    final action = (widget.initialAction ?? '').toLowerCase();
    if (action == 'refund') {
      final refundable = o.items.where((i) => i.canRequestRefund);
      if (refundable.isNotEmpty) {
        _requestRefund(refundable.first);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items are eligible for a refund')),
        );
      }
    } else if (action == 'review') {
      final reviewable = o.items.where((i) => i.canReview);
      if (reviewable.isNotEmpty) {
        _writeReview(reviewable.first);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items left to review on this order')),
        );
      }
    }
  }

  int _paidStepIndex(String status) {
    switch (status) {
      case 'pending':
      case 'processing':
        return 0;
      case 'call_confirmed':
      case 'packed':
        return 1;
      case 'shipped':
        return 2;
      case 'awaiting_confirmation':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  String _prettyStatus(String? raw) {
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
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('M/d/yyyy, h:mm:ss a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  Color _fulfillmentBadgeColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'delivered':
        return AppColors.emerald;
      case 'cancelled':
        return AppColors.danger;
      case 'shipped':
      case 'awaiting_confirmation':
        return const Color(0xFF7C3AED);
      case 'packed':
        return AppColors.blue;
      default:
        return const Color(0xFF7C3AED);
    }
  }

  bool _canConfirm(OrderItemModel item) {
    final s = (item.status ?? '').toLowerCase();
    return s == 'awaiting_confirmation' || s.contains('awaiting');
  }

  Future<void> _messageSeller() async {
    final o = order;
    if (o?.sellerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller chat is unavailable for this order')),
      );
      return;
    }
    try {
      final opened = await context.read<AppStore>().openConversation(sellerId: o!.sellerId!);
      if (!mounted) return;
      context.push('/messages/${opened.conversation.id}');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer')),
      );
    }
  }

  Future<void> _requestRefund(OrderItemModel item) async {
    String reason = 'wrong_item';
    final descCtrl = TextEditingController();
    final ok = await showAppSheet<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SheetShell(
              action: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (descCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Please describe the issue')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text(
                    'Submit request',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              children: [
                const Text('Request a refund', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  item.productName,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Admin will review before any refund is approved.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'wrong_item', child: Text('Wrong item received')),
                    DropdownMenuItem(value: 'damaged_item', child: Text('Damaged item')),
                    DropdownMenuItem(value: 'not_delivered', child: Text('Not delivered')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) {
                    if (v != null) setModal(() => reason = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Explain why you need a refund',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    final description = descCtrl.text.trim();
    descCtrl.dispose();
    if (ok != true || !mounted) return;
    try {
      await context.read<AppStore>().requestRefund(
            orderId: order!.id,
            orderItemId: item.id,
            reason: reason,
            description: description,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund request submitted')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _cancelRefund(int disputeId) async {
    try {
      await context.read<AppStore>().cancelRefund(disputeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund request cancelled')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _writeReview(OrderItemModel item) async {
    int rating = 5;
    final commentCtrl = TextEditingController();
    final ok = await showAppSheet<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SheetShell(
              action: SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Submit review',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              children: [
                const Text('Write a review', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  item.productName,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        onPressed: () => setModal(() => rating = i),
                        icon: Icon(
                          i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: const Color(0xFFF59E0B),
                          size: 36,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Comment (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    final comment = commentCtrl.text.trim();
    commentCtrl.dispose();
    if (ok != true || !mounted) return;
    try {
      await context.read<AppStore>().submitReview(
            orderId: order!.id,
            orderItemId: item.id,
            rating: rating,
            comment: comment.isEmpty ? null : comment,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your review!')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _printOrder() async {
    final o = order;
    if (o == null) return;
    try {
      await printOrderReceipt(o);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not print: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final status = (o?.status ?? 'pending').toLowerCase();
    final pay = (o?.paymentStatus ?? '').toLowerCase();
    final method = (o?.paymentMethod ?? o?.paymentChannel ?? 'momo').toLowerCase();
    final paid = pay == 'paid';
    final underReview = o?.directPaymentUnderReview ?? false;
    final step = _paidStepIndex(status);
    final showProgress = paid || underReview || method == 'cash';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: InkWell(
          onTap: () => goBackOr(context, '/shop?tab=orders'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back, size: 20),
                const SizedBox(width: 8),
                Text(
                  o == null ? 'Order' : 'Back to purchase',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (o != null)
            TextButton.icon(
              onPressed: _printOrder,
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print'),
            ),
          if (o?.sellerId != null)
            IconButton(
              tooltip: 'Chat seller',
              onPressed: _messageSeller,
              icon: const Icon(Icons.chat_bubble_outline),
            ),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading order…')
          : error != null
              ? Center(child: Text(error!))
              : o == null
                  ? const Center(child: Text('Order not found'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          o.orderNumber,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 20,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Placed on ${_formatPlaced(o.createdAt)}',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _PillBadge(
                                        label: paid
                                            ? 'PAID'
                                            : underReview
                                                ? 'PROCESSING'
                                                : _prettyStatus(o.paymentStatus).toUpperCase(),
                                        color: paid ? AppColors.emerald : AppColors.accent,
                                      ),
                                      if (status != 'cancelled') ...[
                                        const SizedBox(height: 6),
                                        _PillBadge(
                                          label: _prettyStatus(o.status).toUpperCase(),
                                          color: _fulfillmentBadgeColor(o.status),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              if (showProgress && status != 'cancelled') ...[
                                const SizedBox(height: 18),
                                const Divider(height: 1),
                                const SizedBox(height: 14),
                                const Text('Order progress', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                const SizedBox(height: 14),
                                _OrderProgressStepper(
                                  steps: _paidSteps,
                                  currentIndex: step,
                                  completed: status == 'delivered',
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: Text(
                                    _prettyStatus(o.status),
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              const Text('Deliver to', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: 6),
                              Text(o.receiverName ?? '—', style: const TextStyle(color: AppColors.textSecondary)),
                              if ((o.receiverPhone ?? '').isNotEmpty)
                                InkWell(
                                  onTap: () => _callPhone(o.receiverPhone!),
                                  child: Text(
                                    o.receiverPhone!,
                                    style: const TextStyle(color: AppColors.textSecondary),
                                  ),
                                ),
                              Text(
                                [
                                  if ((o.deliveryNotes ?? '').trim().isNotEmpty) o.deliveryNotes!.trim(),
                                  if ((o.digitalAddress ?? '').trim().isNotEmpty) o.digitalAddress!.trim(),
                                  [o.city, o.region]
                                      .whereType<String>()
                                      .where((s) => s.trim().isNotEmpty)
                                      .join(', '),
                                ].where((s) => s.trim().isNotEmpty).join('\n'),
                                style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
                              ),
                              const SizedBox(height: 16),
                              const Text('Payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: 6),
                              Text(
                                method == 'cash'
                                    ? 'Cash on delivery'
                                    : (o.paymentMethod ?? o.paymentChannel ?? 'Mobile Money'),
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                              if (underReview) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Payment sent · waiting for the seller to confirm'
                                  '${(o.directPaymentReference ?? '').isNotEmpty ? ' (ref ${o.directPaymentReference})' : ''}',
                                  style: const TextStyle(
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ] else if (o.directPaymentRejected) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Payment not confirmed: ${o.directPaymentRejectionReason}',
                                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Seller information', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        StoreAvatar(
                                          name: o.storeName,
                                          photo: o.storeLogo,
                                          radius: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            o.storeName ?? 'Seller',
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                          ),
                                        ),
                                        if ((o.storeSlug ?? '').isNotEmpty)
                                          TextButton(
                                            onPressed: () => context.push('/stores/${o.storeSlug}'),
                                            style: TextButton.styleFrom(
                                              foregroundColor: AppColors.primary,
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            child: const Text('Visit >', style: TextStyle(fontWeight: FontWeight.w800)),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Divider(height: 1),
                              const SizedBox(height: 14),
                              const Text('Items', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              for (final item in o.items) ...[
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 56,
                                        height: 56,
                                        color: AppColors.background,
                                        child: (item.imageUrl == null || item.imageUrl!.isEmpty)
                                            ? const Icon(Icons.image_outlined, color: AppColors.textMuted)
                                            : CachedNetworkImage(imageUrl: item.imageUrl!, fit: BoxFit.cover),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${item.productName} × ${item.quantity}',
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 6),
                                          _PillBadge(
                                            label: _prettyStatus(item.status ?? o.status),
                                            color: _fulfillmentBadgeColor(item.status ?? o.status),
                                          ),
                                          if (item.hasDeliveryDetails) ...[
                                            const SizedBox(height: 10),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: const Color(0xFFBFDBFE)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Delivery details',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 14,
                                                      color: Color(0xFF1E3A8A),
                                                    ),
                                                  ),
                                                  if ((item.driverPhone ?? '').trim().isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    InkWell(
                                                      onTap: () => _callPhone(item.driverPhone!),
                                                      child: Text(
                                                        'Driver: ${item.driverPhone}',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w700,
                                                          color: Color(0xFF1D4ED8),
                                                          decoration: TextDecoration.underline,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  if ((item.vehicleNumber ?? '').trim().isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Vehicle: ${item.vehicleNumber}',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF1E3A8A),
                                                      ),
                                                    ),
                                                  ],
                                                  if ((item.packageImageUrl ?? '').trim().isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    InkWell(
                                                      onTap: () => showImageViewer(
                                                        context,
                                                        urls: [item.packageImageUrl!],
                                                      ),
                                                      child: const Text(
                                                        'View package image',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w800,
                                                          color: Color(0xFF1D4ED8),
                                                          decoration: TextDecoration.underline,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    InkWell(
                                                      onTap: () => showImageViewer(
                                                        context,
                                                        urls: [item.packageImageUrl!],
                                                      ),
                                                      borderRadius: BorderRadius.circular(10),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(10),
                                                        child: CachedNetworkImage(
                                                          imageUrl: item.packageImageUrl!,
                                                          height: 96,
                                                          width: 96,
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (_canConfirm(item)) ...[
                                            const SizedBox(height: 10),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFF7ED),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: const Color(0xFFFED7AA)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Waiting for delivery confirmation',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 14,
                                                      color: Color(0xFF431407),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    item.autoConfirmIn == null || item.autoConfirmIn!.isEmpty
                                                        ? 'Confirm delivery if you have received the products.'
                                                        : 'Confirm delivery if you have received the products. The system will confirm delivery automatically in ${item.autoConfirmIn}.',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      height: 1.35,
                                                      color: Color(0xFF9A3412),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: ElevatedButton.icon(
                                                      onPressed: () async {
                                                        try {
                                                          await context.read<AppStore>().confirmDelivery(o.id, item.id);
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(content: Text('Delivery confirmed')),
                                                            );
                                                            _load();
                                                          }
                                                        } on ApiException catch (e) {
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(content: Text(e.message)),
                                                            );
                                                          }
                                                        }
                                                      },
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: AppColors.accent,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                                      ),
                                                      icon: const Icon(Icons.check_circle_outline, size: 18),
                                                      label: const Text(
                                                        'Confirm delivery',
                                                        style: TextStyle(fontWeight: FontWeight.w800),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (item.dispute != null) ...[
                                            const SizedBox(height: 10),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFFBEB),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: const Color(0xFFFDE68A)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Refund: ${(item.dispute!['status'] ?? '').toString().replaceAll('_', ' ')}',
                                                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    (item.dispute!['reason'] ?? '').toString().replaceAll('_', ' '),
                                                    style: const TextStyle(color: Color(0xFFB45309)),
                                                  ),
                                                  if ((item.dispute!['description'] ?? '').toString().trim().isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '${item.dispute!['description']}',
                                                      style: const TextStyle(color: Color(0xFF92400E), fontSize: 13),
                                                    ),
                                                  ],
                                                  if (['open', 'under_review']
                                                      .contains((item.dispute!['status'] ?? '').toString())) ...[
                                                    const SizedBox(height: 8),
                                                    TextButton(
                                                      onPressed: () => _cancelRefund((item.dispute!['id'] as num).toInt()),
                                                      child: const Text('Cancel refund request'),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ] else if (item.canRequestRefund) ...[
                                            const SizedBox(height: 8),
                                            TextButton.icon(
                                              onPressed: () => _requestRefund(item),
                                              style: TextButton.styleFrom(
                                                foregroundColor: AppColors.danger,
                                                padding: EdgeInsets.zero,
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              icon: const Icon(Icons.warning_amber_rounded, size: 16),
                                              label: const Text(
                                                'Request refund',
                                                style: TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                              ),
                                            ),
                                          ],
                                          if (item.buyerReview != null) ...[
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'You rated ${item.buyerReview!['rating']}/5',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ] else if (item.canReview) ...[
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                onPressed: () => _writeReview(item),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.accent,
                                                  foregroundColor: Colors.white,
                                                ),
                                                icon: const Icon(Icons.rate_review_outlined, size: 18),
                                                label: const Text('Write review'),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _money.format(item.displayTotal),
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              _moneyRow('Subtotal', o.subtotal),
                              _moneyRow('Shipping', o.shippingCost),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                  const Spacer(),
                                  Text(
                                    _money.format(o.total),
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.accent),
                                  ),
                                ],
                              ),
                              if (o.needsDirectPaymentProof) ...[
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    onPressed: () => context.push('/orders/${o.id}/direct-pay'),
                                    icon: const Icon(Icons.payments_outlined, size: 18),
                                    label: Text(
                                      (o.directPaymentProofPath ?? '').isNotEmpty ||
                                              (o.directPaymentReference ?? '').isNotEmpty
                                          ? 'Update direct payment proof'
                                          : 'Pay seller directly',
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: OutlinedButton.icon(
                                  onPressed: _printOrder,
                                  icon: const Icon(Icons.print_outlined, size: 18),
                                  label: const Text('Print receipt'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _moneyRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(_money.format(value), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      color: const Color(0xFF9A3412),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.3),
      ),
    );
  }
}

class _OrderProgressStepper extends StatelessWidget {
  const _OrderProgressStepper({
    required this.steps,
    required this.currentIndex,
    required this.completed,
  });

  final List<String> steps;
  final int currentIndex;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final progress = completed
        ? 1.0
        : (currentIndex / (steps.length - 1)).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Builder(
                      builder: (_) {
                        final done = completed ? i <= currentIndex : i < currentIndex;
                        final active = !completed && i == currentIndex;
                        return Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: done
                                ? AppColors.emerald
                                : active
                                    ? AppColors.accent
                                    : const Color(0xFFF3F4F6),
                            shape: BoxShape.circle,
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent.withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: done
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: active ? Colors.white : AppColors.textMuted,
                                  ),
                                ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[i],
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.15,
                        fontWeight: (!completed && i == currentIndex) || (completed && i == currentIndex)
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: (!completed && i == currentIndex)
                            ? AppColors.accent
                            : (completed && i == currentIndex)
                                ? AppColors.emerald
                                : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: const Color(0xFFF3F4F6),
            color: completed ? AppColors.emerald : AppColors.accent,
          ),
        ),
      ],
    );
  }
}

class _Guest extends StatelessWidget {
  const _Guest({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 40, color: AppColors.accent),
          const SizedBox(height: 12),
          const Text('Login to continue', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onLogin, child: const Text('Login')),
        ],
      ),
    );
  }
}
