import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/momo_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _stamp = DateFormat('d MMM yyyy, h:mm a');

/// Cash out to mobile money, mirroring the web wallet's withdrawal flow: pick a
/// network, confirm the MoMo details, then review before the request goes in.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  bool loading = true;
  bool submitting = false;
  String? error;
  WithdrawalOverview overview = const WithdrawalOverview();

  String network = 'mtn';
  final numberCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    numberCtrl.dispose();
    nameCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadWithdrawals();
      if (!mounted) return;
      setState(() {
        overview = data;
        loading = false;
      });
      // Only seed the fields once, so a reload never overwrites typing.
      if (!_prefilled) {
        _prefilled = true;
        numberCtrl.text = data.defaultMomoNumber ?? '';
        nameCtrl.text = data.defaultAccountName ?? '';
      }
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

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _withdrawAll() {
    setState(() => amountCtrl.text = overview.availableBalance.toStringAsFixed(2));
  }

  /// Validates locally, shows the review sheet, then sends the request.
  Future<void> _submit() async {
    final amount = double.tryParse(amountCtrl.text.trim());
    final number = numberCtrl.text.trim();
    final name = nameCtrl.text.trim();

    if (number.replaceAll(RegExp(r'\D'), '').length < 9) {
      _toast('Enter the MoMo number that should receive the money');
      return;
    }
    if (name.isEmpty) {
      _toast('Enter the name on the MoMo account');
      return;
    }
    if (amount == null || amount < overview.minimum) {
      _toast('Minimum withdrawal is ${_money.format(overview.minimum)}');
      return;
    }
    if (amount > overview.availableBalance) {
      _toast('You can withdraw at most ${_money.format(overview.availableBalance)}');
      return;
    }

    final confirmed = await _review(amount, number, name);
    if (confirmed != true || !mounted) return;

    setState(() => submitting = true);
    try {
      await context.read<AppStore>().requestWithdrawal(
            amount: amount,
            momoNumber: number,
            accountName: name,
            network: network,
          );
      if (!mounted) return;
      amountCtrl.clear();
      _toast('Withdrawal requested. Payouts are usually sent within 1 hour.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('$e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<bool?> _review(double amount, String number, String name) {
    return showAppSheet<bool>(
      context: context,
      builder: (ctx) => SheetShell(
        action: SizedBox(
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Request withdrawal to MoMo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
        children: [
          const Text('Check your payout details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          const Text(
            'Money goes to this MoMo account. Wrong details can delay your payout.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.ringOrange,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MomoNetworkLogo(network: network, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            momoNetworkLabel(network),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(number, style: const TextStyle(color: AppColors.textSecondary)),
                          Text(name, style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _money.format(amount),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Usually paid within 1 hour after admin approval.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdraw'),
        leading: BackButton(onPressed: () => goBackOr(context, '/shop?tab=wallet')),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading your balance…')
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
    final tooSmall = overview.availableBalance < overview.minimum;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          _BalanceCard(
            available: overview.availableBalance,
            onWithdrawAll: tooSmall || overview.hasPending ? null : _withdrawAll,
          ),
          const SizedBox(height: 16),
          if (overview.hasPending)
            const _Notice(
              icon: Icons.hourglass_top_rounded,
              title: 'Withdrawal in processing',
              body: 'Please wait for your current request to finish (usually within 1 hour) '
                  'before asking for another one.',
            )
          else if (tooSmall)
            _Notice(
              icon: Icons.info_outline_rounded,
              title: 'Minimum withdrawal is ${_money.format(overview.minimum)}',
              body: 'Your available balance is ${_money.format(overview.availableBalance)}. '
                  'Sell or add funds first, then come back to cash out.',
            )
          else
            _Card(
              children: [
                const Text(
                  '1. Choose your network',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'MTN MoMo is the most common. Pick the network of the number below.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 12),
                for (final item in momoNetworks) ...[
                  _NetworkTile(
                    network: item,
                    selected: network == item.id,
                    onTap: () => setState(() => network = item.id),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                const Text(
                  '2. Where should the money go?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numberCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
                  decoration: const InputDecoration(
                    labelText: 'MoMo number',
                    hintText: '0XX XXX XXXX',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Account name',
                    hintText: 'Name registered on the MoMo number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '3. How much?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount (GH₵)',
                    helperText: 'Minimum ${_money.format(overview.minimum)}'
                        ' · Available ${_money.format(overview.availableBalance)}',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFFED7AA),
                    ),
                    onPressed: submitting ? null : _submit,
                    child: Text(
                      submitting ? 'Sending…' : 'Review withdrawal',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          if (overview.items.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Withdrawal requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            for (final item in overview.items) ...[
              _WithdrawalRow(item: item),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.available, this.onWithdrawAll});

  final double available;
  final VoidCallback? onWithdrawAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available to withdraw',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            _money.format(available),
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
          ),
          if (onWithdrawAll != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onWithdrawAll,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'Withdraw all',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E), height: 1.35),
                ),
              ],
            ),
          ),
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
    required this.onTap,
  });

  final MomoNetwork network;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
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
                    if (network.id == 'mtn')
                      Text(
                        'MOST COMMON',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: selected ? network.accent : AppColors.textMuted,
                        ),
                      ),
                    Text(
                      network.label,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? network.selectedBorder : AppColors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow({required this.item});

  final WithdrawalItem item;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (item.status) {
      'paid' => (const Color(0xFFECFDF5), const Color(0xFF047857)),
      'rejected' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C)),
      'processing' => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
      _ => (const Color(0xFFFFFBEB), const Color(0xFFB45309)),
    };
    final stamp = DateTime.tryParse(item.processedAt ?? item.createdAt ?? '')?.toLocal();

    return Container(
      padding: const EdgeInsets.all(12),
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
              MomoNetworkLogo(network: item.network, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.statusLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.momoNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stamp == null ? item.networkLabel : '${item.networkLabel} · ${_stamp.format(stamp)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _money.format(item.amount),
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.accent),
              ),
            ],
          ),
          if ((item.rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.rejectionReason!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
