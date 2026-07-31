import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class DirectPaymentScreen extends StatefulWidget {
  const DirectPaymentScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<DirectPaymentScreen> createState() => _DirectPaymentScreenState();
}

class _DirectPaymentScreenState extends State<DirectPaymentScreen> {
  bool loading = true;
  bool submitting = false;
  String? error;
  OrderModel? order;
  final refCtrl = TextEditingController();
  XFile? proof;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    refCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final o = await context.read<AppStore>().fetchOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        order = o;
        refCtrl.text = o.directPaymentReference ?? '';
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

  Future<void> _pickProof() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => proof = file);
  }

  Future<void> _submit() async {
    final o = order;
    if (o == null) return;
    final reference = refCtrl.text.trim();
    if (reference.isEmpty && proof == null && (o.directPaymentProofPath ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload a payment screenshot or enter a transaction ID')),
      );
      return;
    }
    setState(() => submitting = true);
    try {
      await context.read<AppStore>().submitDirectPayment(
            orderId: o.id,
            reference: reference.isEmpty ? null : reference,
            proofPath: proof?.path,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment proof submitted. Waiting for seller confirmation.')),
      );
      context.go('/orders/${o.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final method = o?.sellerPaymentMethod;

    return Scaffold(
      appBar: AppBar(title: const Text('Pay seller directly')),
      body: loading
          ? const FullPageLoader(label: 'Loading payment details…')
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
                    Text(
                      o?.orderNumber ?? 'Order',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send ${_money.format(o?.total ?? 0)} to ${o?.storeName ?? 'the seller'}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pay into this account', style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          if (method == null)
                            const Text(
                              'Seller payment details are unavailable. Chat the seller for MoMo/bank details.',
                              style: TextStyle(color: AppColors.textSecondary),
                            )
                          else ...[
                            Text(
                              '${method['display_label'] ?? method['label'] ?? 'Payment method'}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            if ((method['account_name'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('Name: ${method['account_name']}'),
                            ],
                            if ((method['account_number'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(child: Text('Number: ${method['account_number']}')),
                                  IconButton(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: '${method['account_number']}'),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Account number copied')),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.copy, size: 18),
                                  ),
                                ],
                              ),
                            ],
                            if ((method['network'] ?? '').toString().isNotEmpty)
                              Text('Network: ${method['network']}'),
                            if ((method['bank_name'] ?? '').toString().isNotEmpty)
                              Text('Bank: ${method['bank_name']}'),
                            if ((method['instructions'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${method['instructions']}',
                                style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    if ((o?.directPaymentRejectionReason ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Rejected: ${o!.directPaymentRejectionReason}',
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Transaction ID / reference (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickProof,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(proof == null ? 'Upload payment screenshot' : 'Change screenshot'),
                    ),
                    if (proof != null) ...[
                      const SizedBox(height: 8),
                      Text(proof!.name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                    if ((o?.directPaymentProofPath ?? '').isNotEmpty && proof == null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Proof already uploaded. You can replace it or add a transaction ID.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'I\'ve paid — submit proof',
                      loading: submitting,
                      onPressed: submitting ? null : _submit,
                    ),
                  ],
                ),
    );
  }
}
