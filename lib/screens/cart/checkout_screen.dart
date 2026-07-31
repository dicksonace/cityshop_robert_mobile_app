import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Delivery address', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    if (p!.addresses.isEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await context.push('/addresses');
                          _load();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add address'),
                      )
                    else ...[
                      for (final a in p.addresses)
                        RadioListTile<int>(
                          value: a.id,
                          groupValue: addressId,
                          onChanged: (v) => setState(() => addressId = v),
                          title: Text(a.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${a.addressLine}, ${a.city}, ${a.region}\n${a.phone}'),
                          activeColor: AppColors.accent,
                        ),
                      TextButton(
                        onPressed: () async {
                          await context.push('/addresses');
                          _load();
                        },
                        child: const Text('Manage addresses'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('Payment method', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    _PayOption(
                      value: 'momo',
                      group: paymentMethod,
                      title: 'Mobile Money / Card (Paystack)',
                      subtitle: p.paystackConfigured ? 'Secure online payment' : 'Paystack not configured on server',
                      onChanged: (v) => setState(() => paymentMethod = v),
                    ),
                    _PayOption(
                      value: 'wallet',
                      group: paymentMethod,
                      title: 'CityShop Wallet',
                      subtitle: 'Available: ${_money.format(p.walletAvailable)}',
                      onChanged: (v) => setState(() => paymentMethod = v),
                    ),
                    _PayOption(
                      value: 'cash',
                      group: paymentMethod,
                      title: 'Cash on delivery',
                      subtitle: 'Pay when you receive',
                      onChanged: (v) => setState(() => paymentMethod = v),
                    ),
                    if (paymentMethod != 'cash') ...[
                      for (final group in p.sellerGroups) ...[
                        const SizedBox(height: 14),
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
                      ],
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _Row('Subtotal', _money.format(p.subtotal)),
                          _Row('Shipping', _money.format(p.shippingTotal)),
                          const Divider(),
                          _Row('Total', _money.format(p.grandTotal), bold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Place order',
                      loading: placing,
                      onPressed: placing ? null : _place,
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to pay $sellerName',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Package total ${_money.format((group['package_total'] as num?)?.toDouble() ?? 0)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          if (acceptMarketplace)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'marketplace',
              groupValue: channel,
              onChanged: (v) {
                if (v != null) onChannelChanged(v);
              },
              title: const Text('Pay via CityShop (secure)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Paystack MoMo or card'),
              activeColor: AppColors.accent,
            ),
          if (canDirect)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'direct',
              groupValue: channel,
              onChanged: (v) {
                if (v != null) onChannelChanged(v);
              },
              title: const Text('Pay seller directly', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Send MoMo/bank to the seller, then upload proof'),
              activeColor: AppColors.accent,
            ),
          if (channel == 'direct' && canDirect) ...[
            const SizedBox(height: 4),
            const Text('Seller account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            for (final m in methods)
              RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: (m['id'] as num).toInt(),
                groupValue: methodId,
                onChanged: (v) {
                  if (v != null) onMethodChanged(v);
                },
                title: Text(
                  '${m['display_label'] ?? m['label'] ?? 'Account'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                activeColor: AppColors.accent,
              ),
          ],
        ],
      ),
    );
  }
}

class _PayOption extends StatelessWidget {
  const _PayOption({
    required this.value,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final String value;
  final String group;
  final String title;
  final String subtitle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: value,
      groupValue: group,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      activeColor: AppColors.accent,
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? AppColors.accent : null,
            ),
          ),
        ],
      ),
    );
  }
}
