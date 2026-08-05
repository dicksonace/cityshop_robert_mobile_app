import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import 'paystack_payment_screen.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutPreview? preview;
  String? error;
  bool loading = true;
  bool placing = false;
  int? addressId;
  String paymentMethod = 'momo';
  final Map<int, String> sellerChannels = {};
  final Map<int, int?> sellerMethodIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _initSellerPayments(CheckoutPreview p) {
    for (final group in p.sellerGroups) {
      final sellerId = (group['seller_id'] as num?)?.toInt();
      if (sellerId == null) continue;
      final acceptMarketplace = group['accept_marketplace_payments'] != false;
      final acceptDirect = group['accept_direct_payments'] == true;
      final methods = (group['payment_methods'] is List)
          ? (group['payment_methods'] as List).whereType<Map>().toList()
          : <Map>[];
      if (acceptDirect && methods.isNotEmpty) {
        sellerChannels[sellerId] = acceptMarketplace ? 'marketplace' : 'direct';
        sellerMethodIds[sellerId] = (methods.first['id'] as num?)?.toInt();
      } else {
        sellerChannels[sellerId] = 'marketplace';
        sellerMethodIds[sellerId] = null;
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = await context.read<AppStore>().loadCheckoutPreview();
      if (!mounted) return;
      _initSellerPayments(p);
      setState(() {
        preview = p;
        addressId = p.addresses.where((a) => a.isDefault).firstOrNull?.id ??
            p.addresses.firstOrNull?.id;
        if (paymentMethod == 'cash' && _storesWithoutCash(p).isNotEmpty) {
          paymentMethod = 'momo';
        }
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
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

  /// Stores in the cart that switched cash on delivery off. One payment method
  /// covers the whole order, so a single store is enough to rule cash out.
  List<String> _storesWithoutCash(CheckoutPreview p) => p.sellerGroups
      .where((g) => g['accepts_cash'] == false)
      .map((g) => (g['seller_name'] as String?)?.trim())
      .map((name) => (name == null || name.isEmpty) ? 'This store' : name)
      .toList();

  Map<String, dynamic> _sellerPaymentsPayload() {
    if (paymentMethod == 'cash') return {};
    final payload = <String, dynamic>{};
    for (final entry in sellerChannels.entries) {
      final channel = entry.value;
      payload['${entry.key}'] = {
        'channel': channel,
        if (channel == 'direct' && sellerMethodIds[entry.key] != null)
          'method_id': sellerMethodIds[entry.key],
      };
    }
    return payload;
  }

  List<int> _directOrderIds(Map? checkout) {
    final orders = checkout?['orders'];
    if (orders is! List) return [];
    return orders
        .whereType<Map>()
        .where((o) =>
            (o['payment_channel']?.toString().toLowerCase() == 'direct') &&
            (o['payment_status']?.toString().toLowerCase() != 'paid'))
        .map((o) => (o['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  Future<void> _place() async {
    if (addressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a delivery address first')),
      );
      return;
    }

    if (paymentMethod != 'cash') {
      for (final entry in sellerChannels.entries) {
        if (entry.value == 'direct' && sellerMethodIds[entry.key] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Choose a seller payment account for direct pay')),
          );
          return;
        }
      }
    }

    setState(() => placing = true);
    final store = context.read<AppStore>();
    try {
      final sellerPayments = _sellerPaymentsPayload();
      final result = await store.placeCheckout(
        addressId: addressId!,
        paymentMethod: paymentMethod,
        sellerPayments: sellerPayments.isEmpty ? null : sellerPayments,
      );
      final next = result['next'] as String? ?? 'orders';
      final checkout = result['checkout'];
      final checkoutId = checkout is Map ? checkout['id'] as int? : null;
      final directIds = _directOrderIds(checkout is Map ? checkout : null);

      if (!mounted) return;

      final needsPaystack = (paymentMethod == 'momo' || paymentMethod == 'card') &&
          (next == 'paystack_or_direct' || next == 'paystack') &&
          checkoutId != null &&
          (preview?.paystackConfigured ?? false) &&
          sellerChannels.values.any((c) => c == 'marketplace');

      if (needsPaystack) {
        try {
          final pay = await store.initializePaystack(checkoutId);
          if (!mounted) return;
          final url = pay['authorization_url'] as String?;
          final reference = pay['reference'] as String? ?? '';
          if (url != null && url.isNotEmpty) {
            final paid = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => PaystackPaymentScreen(
                  authorizationUrl: url,
                  reference: reference,
                  onVerify: (ref) => store.verifyPaystack(
                    checkoutId: checkoutId,
                    reference: ref,
                  ),
                ),
              ),
            );
            if (!mounted) return;
            if (paid == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Marketplace payment successful')),
              );
            }
          }
        } on ApiException catch (e) {
          // No marketplace amount (all direct) — continue to direct pay.
          if (!e.message.toLowerCase().contains('no marketplace')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            }
          }
        }
      }

      if (!mounted) return;

      if (next == 'direct_pay') {
        final packages = result['packages'];
        final shipping = result['shipping'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ??
                  'Send payment to the seller, then upload proof. No order yet.',
            ),
          ),
        );
        context.go('/checkout/direct-pay', extra: {
          'packages': packages is List ? packages : const [],
          'shipping': shipping is Map ? shipping : null,
        });
        return;
      }

      if (directIds.isNotEmpty || next == 'direct_payment') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']?.toString() ?? 'Complete direct seller payment')),
        );
        final firstDirect = directIds.isNotEmpty ? directIds.first : null;
        if (firstDirect != null) {
          context.go('/orders/$firstDirect/direct-pay');
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']?.toString() ?? 'Order placed')),
      );
      context.go('/shop');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => placing = false);
    }
  }

  Future<void> _openAddresses() async {
    await context.push('/addresses');
    if (mounted) _load();
  }

  Future<void> _pickAddress(List<BuyerAddress> addresses) async {
    final picked = await showAppSheet<int>(
      context: context,
      builder: (ctx) => SheetShell(
        action: OutlinedButton.icon(
          onPressed: () => Navigator.pop(ctx, -1),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add a new address'),
        ),
        children: [
          const Text('Deliver to', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 10),
          for (final a in addresses)
            _AddressPickRow(
              address: a,
              selected: a.id == addressId,
              onTap: () => Navigator.pop(ctx, a.id),
            ),
        ],
      ),
    );

    if (picked == null || !mounted) return;
    if (picked == -1) {
      await _openAddresses();
      return;
    }
    setState(() => addressId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: loading
          ? const FullPageLoader(label: 'Preparing checkout…')
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(child: _form(p!)),
                    _PayBar(
                      total: p.grandTotal,
                      placing: placing,
                      onPressed: placing ? null : _place,
                    ),
                  ],
                ),
    );
  }

  Widget _form(CheckoutPreview p) {
    final selected = p.addresses.where((a) => a.id == addressId).firstOrNull;
    final walletShort = p.walletAvailable < p.grandTotal;
    final noCashStores = _storesWithoutCash(p);
    final cashAllowed = noCashStores.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      children: [
        const _SectionLabel('Deliver to'),
        if (selected == null)
          _AddAddressCard(onTap: _openAddresses)
        else
          _AddressCard(
            address: selected,
            onChange: p.addresses.length > 1 ? () => _pickAddress(p.addresses) : _openAddresses,
            changeLabel: p.addresses.length > 1 ? 'Change' : 'Edit',
          ),
        const SizedBox(height: 14),
        const _SectionLabel('Payment'),
        _CardShell(
          child: Column(
            children: [
              _PayRow(
                icon: Icons.credit_card_rounded,
                title: 'Mobile Money / Card',
                subtitle: p.paystackConfigured ? 'Paystack secure payment' : 'Unavailable right now',
                selected: paymentMethod == 'momo',
                warn: !p.paystackConfigured,
                onTap: () => setState(() => paymentMethod = 'momo'),
              ),
              const _RowDivider(),
              _PayRow(
                icon: Icons.account_balance_wallet_rounded,
                title: 'CityShop Wallet',
                subtitle: walletShort
                    ? '${_money.format(p.walletAvailable)} · not enough'
                    : 'Balance ${_money.format(p.walletAvailable)}',
                selected: paymentMethod == 'wallet',
                warn: walletShort,
                onTap: () => setState(() => paymentMethod = 'wallet'),
              ),
              const _RowDivider(),
              _PayRow(
                icon: Icons.payments_rounded,
                title: 'Cash on delivery',
                subtitle: cashAllowed
                    ? 'Pay when it arrives'
                    : '${noCashStores.join(', ')} ${noCashStores.length == 1 ? 'does' : 'do'} not take cash',
                selected: paymentMethod == 'cash',
                enabled: cashAllowed,
                onTap: () => setState(() => paymentMethod = 'cash'),
              ),
            ],
          ),
        ),
        if (paymentMethod != 'cash')
          for (final group in p.sellerGroups)
            _SellerPayBlock(
              group: group,
              channel: sellerChannels[(group['seller_id'] as num?)?.toInt() ?? 0] ?? 'marketplace',
              methodId: sellerMethodIds[(group['seller_id'] as num?)?.toInt() ?? 0],
              onChannelChanged: (channel) {
                final id = (group['seller_id'] as num?)?.toInt();
                if (id == null) return;
                setState(() {
                  sellerChannels[id] = channel;
                  if (channel == 'direct') {
                    final methods = (group['payment_methods'] is List)
                        ? (group['payment_methods'] as List).whereType<Map>().toList()
                        : <Map>[];
                    sellerMethodIds[id] ??= (methods.firstOrNull?['id'] as num?)?.toInt();
                  }
                });
              },
              onMethodChanged: (methodId) {
                final id = (group['seller_id'] as num?)?.toInt();
                if (id == null) return;
                setState(() => sellerMethodIds[id] = methodId);
              },
            ),
        const SizedBox(height: 14),
        _CardShell(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              _Row('Subtotal', _money.format(p.subtotal)),
              _Row('Shipping', _money.format(p.shippingTotal)),
              const _RowDivider(),
              _Row('Total', _money.format(p.grandTotal), bold: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small muted heading that keeps the sections apart without eating height.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      // Selected rows are tinted edge to edge, so the corners have to clip.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1, color: AppColors.border);
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.onChange,
    required this.changeLabel,
  });

  final BuyerAddress address;
  final VoidCallback onChange;
  final String changeLabel;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.ringOrange,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.location_on_rounded, size: 17, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${address.addressLine}, ${address.city}, ${address.region}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.3),
                ),
                Text(
                  address.phone,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.primary,
            ),
            child: Text(
              changeLabel,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAddressCard extends StatelessWidget {
  const _AddAddressCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: _CardShell(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.add_location_alt_outlined, size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Add a delivery address',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressPickRow extends StatelessWidget {
  const _AddressPickRow({
    required this.address,
    required this.selected,
    required this.onTap,
  });

  final BuyerAddress address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.accent : const Color(0xFFE5E7EB),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${address.addressLine}, ${address.city}, ${address.region} · ${address.phone}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: selected ? AppColors.accent : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Total plus the call to action, always in reach at the bottom of the screen.
class _PayBar extends StatelessWidget {
  const _PayBar({required this.total, required this.placing, required this.onPressed});

  final double total;
  final bool placing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + MediaQuery.viewPaddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
              Text(
                _money.format(total),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.accent),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 170,
            height: 46,
            child: ElevatedButton(
              onPressed: placing ? null : onPressed,
              child: placing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Place order'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerPayBlock extends StatelessWidget {
  const _SellerPayBlock({
    required this.group,
    required this.channel,
    required this.methodId,
    required this.onChannelChanged,
    required this.onMethodChanged,
  });

  final Map<String, dynamic> group;
  final String channel;
  final int? methodId;
  final ValueChanged<String> onChannelChanged;
  final ValueChanged<int> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    final sellerName = '${group['seller_name'] ?? 'Seller'}';
    final acceptMarketplace = group['accept_marketplace_payments'] != false;
    final acceptDirect = group['accept_direct_payments'] == true;
    final methods = (group['payment_methods'] is List)
        ? (group['payment_methods'] as List).whereType<Map>().toList()
        : <Map>[];
    final canDirect = acceptDirect && methods.isNotEmpty;
    if (!canDirect && acceptMarketplace) {
      return const SizedBox.shrink();
    }

    final direct = channel == 'direct';

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _CardShell(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Paying $sellerName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.ringOrange,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _money.format((group['package_total'] as num?)?.toDouble() ?? 0),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (acceptMarketplace && canDirect)
              _Segmented(
                left: 'Via CityShop',
                right: 'Pay seller',
                rightSelected: direct,
                onChanged: (toDirect) => onChannelChanged(toDirect ? 'direct' : 'marketplace'),
              )
            else
              Text(
                canDirect ? 'This seller takes direct payment only' : 'Paid securely through CityShop',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 6),
            Text(
              direct
                  ? 'Send the money yourself, then upload the proof'
                  : 'Held by CityShop until you get the item',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
            if (direct && canDirect) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE0C2)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay to seller account',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Make sure you have a trusted seller before you make payment directly. CityShop does not hold this money.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'SEND TO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              for (final m in methods)
                _AccountRow(
                  label: '${m['display_label'] ?? m['label'] ?? 'Account'}',
                  selected: (m['id'] as num).toInt() == methodId,
                  onTap: () => onMethodChanged((m['id'] as num).toInt()),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two-way switch used for the marketplace / direct choice.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
  });

  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _segment(left, !rightSelected, () => onChanged(false)),
          _segment(right, rightSelected, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF7ED) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent : const Color(0xFFE5E7EB),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One compact payment choice: icon, two lines of text, tick when chosen.
class _PayRow extends StatelessWidget {
  const _PayRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.warn = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool warn;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: selected ? const Color(0xFFFFF7ED) : Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.ringOrange : AppColors.background,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: selected ? AppColors.accent : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: warn ? AppColors.danger : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: selected ? AppColors.accent : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 13.5 : 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 14 : 12.5,
              fontWeight: FontWeight.w800,
              color: bold ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
