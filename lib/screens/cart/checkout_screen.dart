import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

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
      final p = await context.read<AppStore>().loadCheckoutPreview();
      if (!mounted) return;
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

  Future<void> _place() async {
    if (addressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a delivery address first')),
      );
      return;
    }
    setState(() => placing = true);
    final store = context.read<AppStore>();
    try {
      final result = await store.placeCheckout(
        addressId: addressId!,
        paymentMethod: paymentMethod,
      );
      final next = result['next'] as String? ?? 'orders';
      final checkout = result['checkout'];
      final checkoutId = checkout is Map ? checkout['id'] as int? : null;

      if (!mounted) return;

      if (paymentMethod == 'momo' || paymentMethod == 'card') {
        if (checkoutId != null && (preview?.paystackConfigured ?? false)) {
          final pay = await store.initializePaystack(checkoutId);
          final url = pay['authorization_url'] as String?;
          if (url != null && url.isNotEmpty) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Complete payment in the browser, then check Orders.')),
            );
            context.go('/shop');
            return;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']?.toString() ?? 'Checkout created')),
        );
        context.go('/shop');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']?.toString() ?? 'Order placed')),
      );
      if (next == 'orders' || paymentMethod == 'wallet' || paymentMethod == 'cash') {
        context.go('/shop');
      }
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
