import 'package:flutter/material.dart';
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
  const ManualDepositScreen({super.key});

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

  void _selectNetwork(String id) {
    final account = _momoByNetwork[id];
    if (account == null) return;
    setState(() => selectedNetwork = id);
    _showDetails(id, account);
  }

  Future<void> _showDetails(String id, Map account) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              momoNetworkLabel(id),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Copy the number, send from your phone, then submit proof on this page.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 14),
            PaymentDetailsCard(
              accountNumber: _number(account),
              accountName: _name(account),
              network: id,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "I've copied — continue",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      await store.submitWalletTopUp(
        amount: amount,
        network: network,
        proofPath: file.path,
        paymentReference: refCtrl.text.trim(),
        userNote: noteCtrl.text.trim(),
      );
      if (!mounted) return;
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
                'Tap a network to see the number / till and account name — then Copy and send.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              for (final network in momoNetworks) ...[
                _NetworkTile(
                  network: network,
                  selected: selected == network.id,
                  configured: momo.containsKey(network.id),
                  onTap: () => _selectNetwork(network.id),
                ),
                const SizedBox(height: 8),
              ],
              if (selectedAccount != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Paying via ${momoNetworkLabel(selected)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showDetails(selected!, selectedAccount),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: const Color(0xFF0369A1),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'View details again',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
              _ProofPicker(proof: proof, onTap: _pickProof),
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
            const Text('Your recent requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            for (final request in _requests) ...[
              _RequestRow(request: request),
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

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.network,
    required this.selected,
    required this.configured,
    required this.onTap,
  });

  final MomoNetwork network;
  final bool selected;
  final bool configured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? network.selectedFill : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? network.selectedBorder : const Color(0xFFE5E7EB),
          width: selected ? 2 : 1.4,
        ),
      ),
      child: Row(
        children: [
          MomoNetworkLogo(network: network.id, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network.id == 'mtn' ? 'RECOMMENDED' : 'MOMO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: selected ? network.accent : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  network.label,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 1),
                Text(
                  configured ? 'Tap to view & copy' : 'Not configured',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, color: network.selectedBorder, size: 20)
          else if (configured)
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );

    if (!configured) return Opacity(opacity: 0.45, child: tile);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: tile),
    );
  }
}

class _ProofPicker extends StatelessWidget {
  const _ProofPicker({required this.proof, required this.onTap});

  final XFile? proof;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = proof != null;

    return Material(
      color: picked ? const Color(0xFFECFDF5) : AppColors.ringOrange,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: picked ? AppColors.emerald : const Color(0xFFFDBA74)),
          ),
          child: Row(
            children: [
              Icon(
                picked ? Icons.check_circle : Icons.add_photo_alternate_outlined,
                color: picked ? AppColors.emerald : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      picked ? 'Screenshot attached' : 'Screenshot / receipt *',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: picked ? AppColors.emerald : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      picked
                          ? proof!.name
                          : 'Upload a screenshot of your MoMo or bank payment confirmation',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final Map request;

  static const _statusColors = <String, (Color, Color)>{
    'pending': (Color(0xFFFEF3C7), Color(0xFF92400E)),
    'approved': (Color(0xFFD1FAE5), Color(0xFF065F46)),
    'rejected': (Color(0xFFFEE2E2), Color(0xFF991B1B)),
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
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Admin: $notes', style: const TextStyle(fontSize: 12, height: 1.3)),
          ],
        ],
      ),
    );
  }
}
