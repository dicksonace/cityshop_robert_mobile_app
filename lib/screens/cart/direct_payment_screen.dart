import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/momo_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// Buyer screen to pay the seller directly — layout matched to web `direct-pay.tsx`.
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

  bool _isBank(Map<String, dynamic>? method) {
    if (method == null) return false;
    final type = '${method['type'] ?? ''}'.toLowerCase();
    if (type.contains('bank')) return true;
    return (method['bank_name'] ?? '').toString().trim().isNotEmpty &&
        (method['network'] ?? '').toString().trim().isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final method = o?.sellerPaymentMethod;
    final isBank = _isBank(method);
    final accountNumber = '${method?['account_number'] ?? ''}'.trim();
    final accountName = '${method?['account_name'] ?? ''}'.trim();
    final bottomPad = 16 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pay seller directly'),
        leading: BackButton(onPressed: () => goBackOr(context, '/shop?tab=orders')),
      ),
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
                  padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                  children: [
                    _HeroHeader(order: o!),
                    if ((o.directPaymentRejectionReason ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          'Rejected: ${o.directPaymentRejectionReason}',
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _OrderSummaryCard(order: o),
                    const SizedBox(height: 16),
                    if (method == null || accountNumber.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text(
                          'Seller payment details are unavailable. Chat the seller for MoMo/bank details.',
                          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                        ),
                      )
                    else
                      PaymentDetailsCard(
                        accountNumber: accountNumber,
                        accountName: accountName,
                        network: isBank ? null : '${method['network'] ?? ''}',
                        isBank: isBank,
                        bankName: '${method['bank_name'] ?? ''}',
                        hint: isBank
                            ? 'Send ${_money.format(o.total)} to the bank account above, then upload a screenshot or transaction ID below.'
                                '${(method['instructions'] ?? '').toString().trim().isNotEmpty ? ' ${method['instructions']}' : ''}'
                            : 'Send ${_money.format(o.total)} to the number above, then upload a screenshot or SMS ID below.'
                                '${(method['instructions'] ?? '').toString().trim().isNotEmpty ? ' ${method['instructions']}' : ''}',
                      ),
                    const SizedBox(height: 20),
                    const Text(
                      'Upload payment proof',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    _ProofDropZone(
                      proof: proof,
                      alreadyUploaded: (o.directPaymentProofPath ?? '').isNotEmpty && proof == null,
                      onTap: _pickProof,
                      onClear: proof == null ? null : () => setState(() => proof = null),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Transaction ID (optional)',
                        hintText: 'From MoMo or bank SMS — skip if you upload a screenshot',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF86EFAC),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text(
                                'Submit your order',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final shipBits = <String>[
      if ((order.receiverName ?? '').trim().isNotEmpty) order.receiverName!.trim(),
      if ((order.city ?? '').trim().isNotEmpty) order.city!.trim(),
      if ((order.region ?? '').trim().isNotEmpty) order.region!.trim(),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.credit_card_rounded, color: AppColors.accent, size: 40),
          const SizedBox(height: 10),
          const Text(
            'Pay seller directly',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 6),
          const Text(
            'Upload proof of payment or a transaction ID so the seller can confirm.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
          ),
          if (shipBits.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Ship to ${shipBits.join(' · ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            order.orderNumber,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final shippingLabel = order.shippingCost > 0
        ? 'Delivery ${_money.format(order.shippingCost)}'
        : 'Delivery ${_money.format(0)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
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
                      order.storeName ?? 'Seller',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$itemCount item${itemCount == 1 ? '' : 's'} · $shippingLabel',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                _money.format(order.total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          if (order.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < order.items.length && i < 4; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _ItemRow(item: order.items[i]),
            ],
            if (order.items.length > 4) ...[
              const SizedBox(height: 6),
              Text(
                '+${order.items.length - 4} more',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItemModel item;

  @override
  Widget build(BuildContext context) {
    final photo = ApiConfig.resolveMediaUrl(item.imageUrl);

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 40,
            height: 40,
            child: photo.isEmpty
                ? Container(
                    color: AppColors.border,
                    child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textMuted),
                  )
                : CachedNetworkImage(
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(
                      color: AppColors.border,
                      child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textMuted),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${item.productName} · Qty ${item.quantity}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _ProofDropZone extends StatelessWidget {
  const _ProofDropZone({
    required this.proof,
    required this.alreadyUploaded,
    required this.onTap,
    this.onClear,
  });

  final XFile? proof;
  final bool alreadyUploaded;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final picked = proof != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              painter: _UploadDashedPainter(
                color: picked || alreadyUploaded ? const Color(0xFF6EE7B7) : const Color(0xFFCBD5E1),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
                decoration: BoxDecoration(
                  color: picked || alreadyUploaded ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(
                      picked || alreadyUploaded ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
                      size: 36,
                      color: picked || alreadyUploaded ? AppColors.emerald : AppColors.textMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      picked
                          ? proof!.name
                          : alreadyUploaded
                              ? 'Proof already uploaded — tap to replace'
                              : 'Tap to upload payment screenshot',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: picked || alreadyUploaded ? AppColors.emerald : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'JPG, PNG, WEBP, GIF · max 5MB',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (picked && onClear != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Remove screenshot', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        if (picked) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(proof!.path),
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ],
    );
  }
}

class _UploadDashedPainter extends CustomPainter {
  const _UploadDashedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)).deflate(0.75),
      );

    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = (start + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_UploadDashedPainter oldDelegate) => oldDelegate.color != color;
}
