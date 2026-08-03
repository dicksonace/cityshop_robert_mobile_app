import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/momo_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// Pre-order "Pay seller directly" — no order until proof / transaction ID is submitted.
class DirectPayDraftScreen extends StatefulWidget {
  const DirectPayDraftScreen({
    super.key,
    this.initialPackages,
    this.initialShipping,
  });

  final List<Map<String, dynamic>>? initialPackages;
  final Map<String, dynamic>? initialShipping;

  @override
  State<DirectPayDraftScreen> createState() => _DirectPayDraftScreenState();
}

class _DirectPayDraftScreenState extends State<DirectPayDraftScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> packages = [];
  Map<String, dynamic>? shipping;

  final Map<int, TextEditingController> _refCtrls = {};
  final Map<int, XFile?> _proofs = {};
  int? submittingSellerId;

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialPackages;
    if (seeded != null && seeded.isNotEmpty) {
      packages = seeded.map((p) => Map<String, dynamic>.from(p)).toList();
      shipping = widget.initialShipping == null
          ? null
          : Map<String, dynamic>.from(widget.initialShipping!);
      _syncControllers();
      loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in _refCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final ids = packages.map(_sellerId).whereType<int>().toSet();
    for (final id in ids) {
      _refCtrls.putIfAbsent(id, TextEditingController.new);
      _proofs.putIfAbsent(id, () => null);
    }
    final stale = _refCtrls.keys.where((id) => !ids.contains(id)).toList();
    for (final id in stale) {
      _refCtrls.remove(id)?.dispose();
      _proofs.remove(id);
    }
  }

  int? _sellerId(Map<String, dynamic> package) {
    final raw = package['seller_id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  static List<Map<String, dynamic>> _mapsFrom(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  static Map<String, dynamic>? _asStringKeyedMap(dynamic raw) {
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  static String _stringOr(dynamic raw, String fallback) {
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return fallback;
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().fetchDirectPayDraft();
      if (!mounted) return;
      setState(() {
        packages = _mapsFrom(data['packages']);
        shipping = _asStringKeyedMap(data['shipping']);
        _syncControllers();
        loading = false;
        if (packages.isEmpty) {
          error = _stringOr(
            data['message'],
            'No packages to pay. Start checkout again.',
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _pickProof(int sellerId) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _proofs[sellerId] = file);
  }

  Future<void> _submit(Map<String, dynamic> package) async {
    final sellerId = _sellerId(package);
    if (sellerId == null) return;

    final reference = (_refCtrls[sellerId]?.text ?? '').trim();
    final proof = _proofs[sellerId];
    if (reference.isEmpty && proof == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload a payment screenshot or enter a transaction ID')),
      );
      return;
    }

    setState(() => submittingSellerId = sellerId);
    try {
      final data = await context.read<AppStore>().submitDirectPayDraft(
            sellerId: sellerId,
            reference: reference.isEmpty ? null : reference,
            proofPath: proof?.path,
          );
      if (!mounted) return;

      final remaining = _mapsFrom(data['remaining_packages']);
      final next = '${data['next'] ?? ''}';
      final message = _stringOr(
        data['message'],
        'Payment submitted. The seller will confirm once received.',
      );

      if (remaining.isEmpty || next == 'orders') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        context.go('/shop?tab=orders');
        return;
      }

      setState(() {
        packages = remaining;
        _syncControllers();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => submittingSellerId = null);
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
    final bottomPad = 16 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pay seller directly'),
        leading: BackButton(onPressed: () => goBackOr(context, '/shop?tab=cart')),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading payment details…')
          : error != null && packages.isEmpty
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
                    _HeroHeader(shipping: shipping),
                    const SizedBox(height: 16),
                    ..._packageCards(),
                  ],
                ),
    );
  }

  List<Widget> _packageCards() {
    final cards = <Widget>[];
    for (var i = 0; i < packages.length; i++) {
      final pkg = packages[i];
      final sellerId = _sellerId(pkg);
      final refCtrl = sellerId == null ? null : _refCtrls[sellerId];
      if (sellerId == null || refCtrl == null) continue;

      final methodRaw = pkg['payment_method'];
      final method = methodRaw is Map ? Map<String, dynamic>.from(methodRaw) : null;

      if (cards.isNotEmpty) cards.add(const SizedBox(height: 20));
      cards.add(
        _PackageCard(
          package: pkg,
          proof: _proofs[sellerId],
          refCtrl: refCtrl,
          submitting: submittingSellerId == sellerId,
          isBank: _isBank(method),
          onPickProof: () => _pickProof(sellerId),
          onClearProof: () => setState(() => _proofs[sellerId] = null),
          onSubmit: () => _submit(pkg),
        ),
      );
    }
    return cards;
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({this.shipping});

  final Map<String, dynamic>? shipping;

  @override
  Widget build(BuildContext context) {
    final shipBits = <String>[
      if (('${shipping?['receiver_name'] ?? ''}').trim().isNotEmpty)
        '${shipping!['receiver_name']}'.trim(),
      if (('${shipping?['city'] ?? ''}').trim().isNotEmpty) '${shipping!['city']}'.trim(),
      if (('${shipping?['region'] ?? ''}').trim().isNotEmpty) '${shipping!['region']}'.trim(),
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
            'No order is created until you upload proof or a transaction ID.',
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
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.proof,
    required this.refCtrl,
    required this.submitting,
    required this.isBank,
    required this.onPickProof,
    required this.onClearProof,
    required this.onSubmit,
  });

  final Map<String, dynamic> package;
  final XFile? proof;
  final TextEditingController refCtrl;
  final bool submitting;
  final bool isBank;
  final VoidCallback onPickProof;
  final VoidCallback onClearProof;
  final VoidCallback onSubmit;

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String _itemThumb(Map item) {
    final product = item['product'];
    if (product is! Map) return '';
    final images = product['images'];
    if (images is! List || images.isEmpty) return '';
    final first = images.first;
    if (first is! Map) return '';
    final url = '${first['url'] ?? ''}'.trim();
    if (url.isNotEmpty) return ApiConfig.resolveMediaUrl(url);
    return ApiConfig.resolveMediaUrl('${first['path'] ?? ''}');
  }

  @override
  Widget build(BuildContext context) {
    final sellerName = '${package['seller_name'] ?? 'Seller'}'.trim();
    final packageTotal = _num(package['package_total']);
    final shippingCost = _num(package['shipping_cost']);
    final items = (package['items'] as List?) ?? const [];
    final itemCount = items.fold<int>(0, (sum, item) {
      if (item is! Map) return sum;
      final q = item['quantity'];
      if (q is int) return sum + q;
      return sum + (int.tryParse('$q') ?? 1);
    });
    final shippingLabel = 'Delivery ${_money.format(shippingCost)}';

    final methodRaw = package['payment_method'];
    final method = methodRaw is Map ? Map<String, dynamic>.from(methodRaw) : null;
    final accountNumber = '${method?['account_number'] ?? ''}'.trim();
    final accountName = '${method?['account_name'] ?? ''}'.trim();
    final instructions = '${method?['instructions'] ?? ''}'.trim();

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
                      sellerName.isEmpty ? 'Seller' : sellerName,
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
                _money.format(packageTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < items.length && i < 4; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              if (items[i] is Map) _ItemRow(item: Map<String, dynamic>.from(items[i] as Map), thumb: _itemThumb(items[i] as Map)),
            ],
            if (items.length > 4) ...[
              const SizedBox(height: 6),
              Text(
                '+${items.length - 4} more',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
          const SizedBox(height: 16),
          if (method == null || accountNumber.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
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
                  ? 'Send ${_money.format(packageTotal)} to the bank account above, then upload a screenshot or transaction ID below.'
                      '${instructions.isNotEmpty ? ' $instructions' : ''}'
                  : 'Send ${_money.format(packageTotal)} to the number above, then upload a screenshot or SMS ID below.'
                      '${instructions.isNotEmpty ? ' $instructions' : ''}',
            ),
          const SizedBox(height: 16),
          const Text(
            'Upload payment proof',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          _ProofDropZone(
            proof: proof,
            onTap: onPickProof,
            onClear: proof == null ? null : onClearProof,
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
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting ? null : onSubmit,
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

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.thumb});

  final Map<String, dynamic> item;
  final String thumb;

  @override
  Widget build(BuildContext context) {
    final product = item['product'];
    final name = product is Map
        ? '${product['name'] ?? 'Product'}'
        : 'Product';
    final qtyRaw = item['quantity'];
    final qty = qtyRaw is int ? qtyRaw : (int.tryParse('$qtyRaw') ?? 1);

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 40,
            height: 40,
            child: thumb.isEmpty
                ? Container(
                    color: AppColors.border,
                    child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textMuted),
                  )
                : CachedNetworkImage(
                    imageUrl: thumb,
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
            '$name · Qty $qty',
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
    required this.onTap,
    this.onClear,
  });

  final XFile? proof;
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
                color: picked ? const Color(0xFF6EE7B7) : const Color(0xFFCBD5E1),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
                decoration: BoxDecoration(
                  color: picked ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(
                      picked ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
                      size: 36,
                      color: picked ? AppColors.emerald : AppColors.textMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      picked ? proof!.name : 'Tap to upload payment screenshot',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: picked ? AppColors.emerald : AppColors.textPrimary,
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
