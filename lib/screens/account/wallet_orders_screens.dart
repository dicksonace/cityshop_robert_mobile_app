import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/order_receipt_printer.dart';
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
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _paystackTopUp() async {
    final amountCtrl = TextEditingController();
    String method = 'momo';
    var submitting = false;

    final started = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 16),
                  SizedBox(
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
                      child: Text(submitting ? 'Starting…' : 'Pay to Add Funds'),
                    ),
                  ),
                ],
              ),
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
      await _load();
    }
  }

  Future<void> _topUp() async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String network = 'mtn';
    XFile? proof;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.88;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Top up wallet',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Pay into a CityShop MoMo account, then upload your proof here.',
                              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Amount (GH₵)',
                                prefixText: 'GH₵ ',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final amt in const [20, 50, 100, 200])
                                  ActionChip(
                                    label: Text('GH₵$amt'),
                                    onPressed: () => setModal(() {
                                      amountCtrl.text = '$amt';
                                    }),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: network,
                              decoration: const InputDecoration(labelText: 'Network used'),
                              items: const [
                                DropdownMenuItem(value: 'mtn', child: Text('MTN')),
                                DropdownMenuItem(value: 'telecel', child: Text('Telecel')),
                                DropdownMenuItem(value: 'airteltigo', child: Text('AirtelTigo')),
                              ],
                              onChanged: (v) => setModal(() => network = v ?? 'mtn'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: refCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Payment reference',
                                hintText: 'MoMo transaction ID',
                              ),
                            ),
                            const SizedBox(height: 14),
                            Material(
                              color: proof == null ? AppColors.ringOrange : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  final file = await ImagePicker().pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85,
                                  );
                                  if (file != null) setModal(() => proof = file);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: proof == null ? const Color(0xFFFDBA74) : AppColors.emerald,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        proof == null ? Icons.add_photo_alternate_outlined : Icons.check_circle,
                                        color: proof == null ? AppColors.primary : AppColors.emerald,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              proof == null ? 'Upload payment proof *' : 'Proof selected',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: proof == null ? AppColors.textPrimary : AppColors.emerald,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              proof == null
                                                  ? 'Screenshot of MoMo confirmation'
                                                  : (proof!.name),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, color: AppColors.textMuted),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Submit payment',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final amountText = amountCtrl.text.trim();
    final reference = refCtrl.text.trim();
    final selectedNetwork = network;
    final selectedProof = proof;
    amountCtrl.dispose();
    refCtrl.dispose();

    if (ok != true || !mounted) return;
    final amount = double.tryParse(amountText);
    if (amount == null || amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount (min GH₵10)')),
      );
      return;
    }
    if (selectedProof == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment proof is required')),
      );
      return;
    }

    try {
      await context.read<AppStore>().submitWalletTopUp(
            amount: amount,
            network: selectedNetwork,
            proofPath: selectedProof.path,
            paymentReference: reference,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Top-up submitted for verification')),
      );
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _networkColor(String network) {
    switch (network.toLowerCase()) {
      case 'mtn':
        return const Color(0xFFFFCC00);
      case 'telecel':
        return const Color(0xFFE60000);
      case 'airteltigo':
        return const Color(0xFFED1C24);
      default:
        return AppColors.accent;
    }
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
    final accounts = (funding?['accounts'] is List)
        ? (funding!['accounts'] as List).whereType<Map>().toList()
        : <Map>[];

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Pending: ${_money.format(wallet?.pendingBalance ?? 0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MANUAL TOP-UP',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Paying a large amount? Send money to CityShop MoMo or bank, then submit proof — admin credits your wallet.',
                          style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: _topUp,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: AppColors.primary,
                          ),
                          child: const Text('Use manual payment ›'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 18),
            const Text('Pay into these accounts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              funding?['instructions']?.toString() ??
                  'Send payment to one of the accounts below, then submit your proof and reference so we can credit your wallet.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final acc in accounts)
              _FundingAccountCard(
                network: '${acc['network'] ?? acc['name'] ?? 'Account'}',
                number: '${acc['number'] ?? acc['account_number'] ?? ''}',
                color: _networkColor('${acc['network'] ?? ''}'),
                onCopy: () {
                  final number = '${acc['number'] ?? acc['account_number'] ?? ''}';
                  if (number.isNotEmpty) _copy('Number', number);
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _FundingAccountCard extends StatelessWidget {
  const _FundingAccountCard({
    required this.network,
    required this.number,
    required this.color,
    required this.onCopy,
  });

  final String network;
  final String number;
  final Color color;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              network.isNotEmpty ? network[0].toUpperCase() : 'M',
              style: TextStyle(fontWeight: FontWeight.w900, color: color == const Color(0xFFFFCC00) ? Colors.black87 : color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(network.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(number, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy number',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, color: AppColors.accent),
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
                    const Expanded(
                      child: Text('My orders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
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
    this.onVisitStore,
  });

  final OrderModel order;
  final String headline;
  final String statusLine;
  final VoidCallback onOpen;
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: onOpen,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Buy again'),
                    ),
                    const SizedBox(width: 8),
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
  const OrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool loading = true;
  String? error;
  OrderModel? order;

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
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
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
        title: Text(
          o == null ? 'Order' : 'Back to purchase',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: AppColors.accent,
                                          child: Text(
                                            (o.storeName ?? 'S').substring(0, 1).toUpperCase(),
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                                          ),
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
