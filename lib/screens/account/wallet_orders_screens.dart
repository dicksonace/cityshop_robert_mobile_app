import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/order_receipt_printer.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../cart/paystack_payment_screen.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class WalletTab extends StatefulWidget {
  const WalletTab({super.key});

  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? funding;

  List<WalletTransactionItem> transactions = [];
  int transactionsPage = 0;
  int transactionsLastPage = 1;
  bool loadingMore = false;
  String? transactionsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      setState(() => loading = false);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await store.loadWallet();
      funding = await store.loadManualFunding();
      await _loadTransactions(reset: true);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadTransactions({bool reset = false}) async {
    if (loadingMore) return;
    final nextPage = reset ? 1 : transactionsPage + 1;
    setState(() {
      loadingMore = true;
      transactionsError = null;
    });
    try {
      final page = await context.read<AppStore>().fetchWalletTransactions(page: nextPage);
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

  Future<void> _paystackTopUp() async {
    final amountCtrl = TextEditingController();
    String method = 'momo';
    var submitting = false;

    final started = await showAppSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
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
                    submitting ? 'Starting…' : 'Pay to Add Funds',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              children: [
                const Text(
                  'Add Funds',
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

  /// Manual deposit lives on its own page, mirroring the web flow.
  Future<void> _openManualDeposit() async {
    await context.push('/wallet/manual-deposit');
    if (mounted) await _load();
  }

  Future<void> _openWithdraw() async {
    await context.push('/wallet/withdraw');
    if (!mounted) return;
    await _load();
    _loadTransactions(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.isLoggedIn) {
      return _Guest(onLogin: () => context.push('/login'));
    }
    if (loading) return const FullPageLoader(label: 'Loading wallet…');
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final wallet = store.wallet;
    final enabled = funding?['enabled'] == true || wallet?.manualTopUpEnabled == true;
    final paystackConfigured =
        wallet?.paystackConfigured == true || funding?['paystack_configured'] == true;

    return RefreshIndicator(
      onRefresh: _load,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available balance', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  _money.format(wallet?.availableBalance ?? 0),
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Flexible so a long pending figure never squeezes out the
                    // withdraw button on narrow phones.
                    Flexible(
                      child: Container(
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
                    ),
                    const SizedBox(width: 8),
                    _WithdrawButton(onTap: _openWithdraw),
                  ],
                ),
              ],
            ),
          ),
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
                const Text('Add Funds', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'Top up via Paystack (MoMo or card).',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: paystackConfigured ? const Color(0xFF16A34A) : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: paystackConfigured ? _paystackTopUp : null,
                    child: Text(paystackConfigured ? 'Pay to Add Funds' : 'Top-up unavailable'),
                  ),
                ),
                if (!paystackConfigured) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Online top-up requires Paystack to be configured on the server.',
                    style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
                  ),
                ],
                if (enabled) ...[
                  const SizedBox(height: 12),
                  _ManualDepositPrompt(onTap: _openManualDeposit),
                ],
              ],
            ),
          ),
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
                const Text('Transaction History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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

    return Container(
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
                '${credit ? '+' : ''}${_money.format(tx.amount)}',
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
        ],
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

/// Links the wallet to the manual deposit page, matching the web prompt card.
/// Sits on the balance card so cashing out is one tap from the wallet.
class _WithdrawButton extends StatelessWidget {
  const _WithdrawButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(Icons.arrow_outward_rounded, size: 17, color: AppColors.accent),
              SizedBox(width: 6),
              Text(
                'Withdraw',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualDepositPrompt extends StatelessWidget {
  const _ManualDepositPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F9FF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0891B2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MANUAL TOP-UP',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Paying a large amount?',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Send money to CityShop MoMo or bank, then submit proof — admin credits your wallet.',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Flexible(
                          child: Text(
                            'Use manual payment',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Color(0xFF0369A1),
                            ),
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 14, color: Color(0xFF0369A1)),
                      ],
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

class _OrdersTabState extends State<OrdersTab> {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      setState(() => loading = false);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await store.loadOrders();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
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
        return status != 'cancelled' && pay == 'pending' && method != 'cash';
      case 'processing':
        return pay == 'paid' &&
            const {'pending', 'processing', 'packed', 'call_confirmed'}.contains(status);
      case 'delivery':
        return status == 'shipped' || itemStatuses.contains('shipped');
      case 'confirm':
        return status == 'awaiting_confirmation' ||
            itemStatuses.any((s) => s == 'awaiting_confirmation' || s.contains('deliver'));
      case 'completed':
        return status == 'delivered' && pay == 'paid';
      case 'review':
        return status == 'delivered' && pay == 'paid';
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
    if (status == 'cancelled') return 'Order closed';
    if (pay == 'pending' && method != 'cash') return 'Awaiting payment';
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
    if (pay == 'pending' && method != 'cash') return 'Waiting for payment';
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
    if (!store.isLoggedIn) return _Guest(onLogin: () => context.push('/login'));
    if (loading) return const FullPageLoader(label: 'Loading orders…');
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final orders = store.orders;
    final counts = _counts(orders);
    final filtered = orders.where((o) => _matchesTab(o, activeTab)).toList();

    return RefreshIndicator(
      onRefresh: _load,
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
                      onPressed: () => setState(() => activeTab = 'all'),
                      child: const Text('View all >'),
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
                        onTap: () => setState(() => activeTab = item.key),
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
            color: Colors.white,
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _statusTabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final tab = _statusTabs[index];
                      final active = activeTab == tab.key;
                      final count = counts[tab.key] ?? 0;
                      return InkWell(
                        onTap: () => setState(() => activeTab = tab.key),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: active ? AppColors.accent : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                          child: Text(
                            count > 0 ? '${tab.label} ($count)' : tab.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: active ? AppColors.accent : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
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
    final step = _paidStepIndex(status);
    final showProgress = paid || method == 'cash';

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
                                        label: paid ? 'PAID' : _prettyStatus(o.paymentStatus).toUpperCase(),
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
                                          if (_canConfirm(item)) ...[
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
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
                                                child: const Text('Confirm delivery'),
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
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                onPressed: () => _requestRefund(item),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: AppColors.danger,
                                                  side: const BorderSide(color: AppColors.danger),
                                                ),
                                                icon: const Icon(Icons.report_gmailerrorred_outlined, size: 18),
                                                label: const Text('Apply for refund'),
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
