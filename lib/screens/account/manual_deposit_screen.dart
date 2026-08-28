import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/momo_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _stamp = DateFormat('d MMM yyyy, h:mm a');

/// Manual deposit, laid out like the web `/wallet/manual-top-up` page: pick a
/// network, copy the CityShop number, then submit proof for admin review.
class ManualDepositScreen extends StatefulWidget {
  const ManualDepositScreen({super.key, this.initialNetwork});

  /// Pre-select mtn|telecel|airteltigo when opened from the recharge sheet.
  final String? initialNetwork;

  @override
  State<ManualDepositScreen> createState() => _ManualDepositScreenState();
}

class _ManualDepositScreenState extends State<ManualDepositScreen> {
  bool loading = true;
  bool submitting = false;
  String? error;
  Map<String, dynamic>? funding;

  String? selectedNetwork;
  final amountCtrl = TextEditingController();
  final refCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  XFile? proof;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    refCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadManualFunding();
      if (!mounted) return;
      setState(() {
        funding = data;
        loading = false;
        _ensureDefaultNetwork();
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
        error = '$e';
        loading = false;
      });
    }
  }

  List<Map> get _accounts {
    final raw = funding?['accounts'];
    return raw is List ? raw.whereType<Map>().toList() : const <Map>[];
  }

  List<Map> get _requests {
    final raw = funding?['requests'];
    return raw is List ? raw.whereType<Map>().toList() : const <Map>[];
  }

  /// First configured account per network, keyed mtn|telecel|airteltigo.
  Map<String, Map> get _momoByNetwork {
    final map = <String, Map>{};
    for (final account in _accounts) {
      if (account['type'] == 'bank') continue;
      final id = normalizeMomoNetworkId('${account['network'] ?? ''}');
      if (id != null && !map.containsKey(id)) map[id] = account;
    }
    return map;
  }

  List<Map> get _bankAccounts => _accounts.where((a) => a['type'] == 'bank').toList();

  String _number(Map account) => '${account['account_number'] ?? account['number'] ?? ''}';

  String _name(Map account) => '${account['account_name'] ?? account['name'] ?? ''}';

  void _ensureDefaultNetwork() {
    final preferred = widget.initialNetwork;
    if (preferred != null && _momoByNetwork.containsKey(preferred)) {
      selectedNetwork = preferred;
      return;
    }
    if (selectedNetwork != null && _momoByNetwork.containsKey(selectedNetwork)) return;
    for (final id in ['mtn', 'telecel', 'airteltigo']) {
      if (_momoByNetwork.containsKey(id)) {
        selectedNetwork = id;
        return;
      }
    }
  }

  void _selectNetwork(String id) {
    if (!_momoByNetwork.containsKey(id)) return;
    setState(() => selectedNetwork = id);
  }

  Future<void> _pickProof() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null && mounted) setState(() => proof = file);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final network = selectedNetwork;
    if (network == null) {
      _toast('Choose MTN, Telecel, or AirtelTigo first.');
      return;
    }
    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount < 10) {
      _toast('Enter the amount you sent (min GH₵10).');
      return;
    }
    final file = proof;
    if (file == null) {
      _toast('Attach the payment screenshot or receipt.');
      return;
    }

    setState(() => submitting = true);
    try {
      final store = context.read<AppStore>();
      final created = await store.submitWalletTopUp(
        amount: amount,
        network: network,
        proofPath: file.path,
        paymentReference: refCtrl.text.trim(),
        userNote: noteCtrl.text.trim(),
      );
      if (!mounted) return;
      final id = (created['id'] as num?)?.toInt();
      if (id != null) {
        context.push('/wallet/manual-deposit/$id');
        return;
      }
      _toast('Top-up submitted — we credit your wallet once an admin verifies it.');
      amountCtrl.clear();
      refCtrl.clear();
      noteCtrl.clear();
      setState(() => proof = null);
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('$e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _cancelRequest(Map request) async {
    final id = (request['id'] as num?)?.toInt();
    if (id == null || '${request['status']}' != 'pending') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel request?'),
        content: const Text('This pending deposit will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel request')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppStore>().cancelManualTopUp(id);
      if (!mounted) return;
      _toast('Deposit request cancelled.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual deposit'),
        leading: BackButton(onPressed: () => goBackOr(context, '/shop?tab=wallet')),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading payment accounts…')
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
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final instructions = '${funding?['instructions'] ?? ''}'.trim();
    final momo = _momoByNetwork;
    final selected = selectedNetwork;
    final selectedAccount = selected == null ? null : momo[selected];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          const Text(
            'Manual deposit',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose MTN, Telecel, or AirtelTigo — we show the CityShop number to pay. Then submit proof.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: Text(
                instructions,
                style: const TextStyle(color: Color(0xFF1E3A8A), fontSize: 13, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Card(
            children: [
              const Text(
                '1. Choose payment method',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap a network, copy the CityShop number, send payment, then submit proof below.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 14),
              MomoNetworkPicker(
                value: selected,
                enabledNetworks: momo.keys.toSet(),
                onChanged: _selectNetwork,
                label: 'Pay with',
                hint: 'Tap to change',
              ),
              if (selectedAccount != null && selected != null) ...[
                const SizedBox(height: 14),
                PaymentDetailsCard(
                  accountNumber: _number(selectedAccount),
                  accountName: _name(selectedAccount),
                  network: selected,
                  hint: 'Send the exact amount, then fill the proof form below.',
                ),
              ],
            ],
          ),
          if (_bankAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Or pay by bank', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            for (final account in _bankAccounts) ...[
              PaymentDetailsCard(
                accountNumber: _number(account),
                accountName: _name(account),
                isBank: true,
                bankName: '${account['bank_name'] ?? ''}',
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 16),
          _Card(
            children: [
              const Text(
                '2. After you pay — submit proof',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'We credit your wallet once an admin verifies the transfer.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount sent (GH₵)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Payment reference / ID (optional)',
                  hintText: 'From MoMo or bank SMS',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Upload payment proof',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _ProofDropZone(
                proof: proof,
                onTap: _pickProof,
                onClear: proof == null ? null : () => setState(() => proof = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Anything else we should know',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFBBF7D0),
                  ),
                  onPressed: submitting || selected == null ? null : _submit,
                  child: Text(
                    submitting ? 'Submitting…' : "I've paid — submit for verification",
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              if (selected == null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Choose a payment method above first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
                ),
              ],
            ],
          ),
          if (_requests.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Recent Deposit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            for (final request in _requests) ...[
              _RequestRow(
                request: request,
                onView: () {
                  final id = (request['id'] as num?)?.toInt();
                  if (id != null) context.push('/wallet/manual-deposit/$id');
                },
                onCancel: () => _cancelRequest(request),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
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

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.onView,
    required this.onCancel,
  });

  final Map request;
  final VoidCallback onView;
  final VoidCallback onCancel;

  static const _statusColors = <String, (Color, Color)>{
    'pending': (Color(0xFFFEF3C7), Color(0xFF92400E)),
    'approved': (Color(0xFFD1FAE5), Color(0xFF065F46)),
    'rejected': (Color(0xFFFEE2E2), Color(0xFF991B1B)),
    'cancelled': (Color(0xFFF3F4F6), Color(0xFF4B5563)),
  };

  String get _when {
    final raw = '${request['created_at'] ?? ''}';
    if (raw.isEmpty) return '';
    try {
      return _stamp.format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${request['status'] ?? 'pending'}';
    final colors = _statusColors[status] ?? (AppColors.border, AppColors.textSecondary);
    final reference = '${request['payment_reference'] ?? ''}';
    final notes = '${request['admin_notes'] ?? ''}';
    final amount = (request['amount'] as num?)?.toDouble() ?? 0;
    final pending = status == 'pending';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _money.format(amount),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.$1,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(color: colors.$2, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [if (reference.isNotEmpty) 'Ref: $reference', _when].where((p) => p.isNotEmpty).join(' · '),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          if (notes.isNotEmpty && status != 'cancelled') ...[
            const SizedBox(height: 4),
            Text('Admin: $notes', style: const TextStyle(fontSize: 12, height: 1.3)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View full details'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF5B21B6),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (pending) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancel request'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
