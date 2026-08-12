import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../data/ghana_banks.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/bank_picker_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/momo_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _stamp = DateFormat('d MMM yyyy, h:mm a');

/// Cash out to MoMo or a Ghana bank account.
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

  String payoutType = 'momo';
  String network = 'mtn';
  final numberCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  bool _prefilled = false;

  bool get _isBank => payoutType == 'bank';

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
      // Only seed MoMo number once. Account name stays blank — user must enter
      // the name registered on MoMo/bank (never prefill fee/minimum leftovers).
      if (!_prefilled) {
        _prefilled = true;
        numberCtrl.text = data.defaultMomoNumber ?? '';
        nameCtrl.text = '';
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
    final max = overview.maxWithdrawable(payoutType);
    setState(() => amountCtrl.text = max.toStringAsFixed(2));
  }

  void _setPayoutType(String type) {
    if (type == payoutType) return;
    setState(() {
      payoutType = type;
      network = type == 'bank' ? (ghanaBanks.isNotEmpty ? ghanaBanks.first.id : 'gcb') : 'mtn';
      // Don't carry a MoMo phone into the bank account field (or the reverse).
      numberCtrl.text = type == 'momo' ? (overview.defaultMomoNumber ?? '') : '';
      nameCtrl.text = '';
    });
  }

  /// Validates locally, shows the review sheet, then sends the request.
  Future<void> _submit() async {
    final amount = double.tryParse(amountCtrl.text.trim());
    final number = numberCtrl.text.trim();
    final name = nameCtrl.text.trim();
    final banks = overview.banks.isNotEmpty ? overview.banks : ghanaBanks;
    // Guard against a stale MoMo network id when Bank is selected.
    final selectedNetwork = _isBank
        ? (isGhanaBank(network) ? network : banks.first.id)
        : network;

    if (_isBank) {
      if (number.replaceAll(RegExp(r'\D'), '').length < 6) {
        _toast('Enter a valid bank account number');
        return;
      }
    } else if (number.replaceAll(RegExp(r'\D'), '').length < 9) {
      _toast('Enter the MoMo number that should receive the money');
      return;
    }
    if (name.isEmpty) {
      _toast(_isBank ? 'Enter the name on the bank account' : 'Enter the name on the MoMo account');
      return;
    }
    if (RegExp(r'^\d+([.,]\d+)?$').hasMatch(name)) {
      _toast('Account name must be the name on the account, not a number');
      return;
    }
    if (amount == null || amount < overview.minimum) {
      _toast('Minimum withdrawal is ${_money.format(overview.minimum)}');
      return;
    }
    final fee = overview.feeFor(payoutType, amount);
    final total = amount + fee;
    if (total > overview.availableBalance) {
      _toast(
        fee > 0
            ? 'Needs ${_money.format(total)} (incl. ${_money.format(fee)} fee). Available ${_money.format(overview.availableBalance)}'
            : 'You can withdraw at most ${_money.format(overview.availableBalance)}',
      );
      return;
    }

    if (selectedNetwork != network) {
      setState(() => network = selectedNetwork);
    }

    final confirmed = await _review(amount, number, name);
    if (confirmed != true || !mounted) return;

    final store = context.read<AppStore>();
    if (!(store.user?.hasPaymentPin ?? false)) {
      _toast('Set a payment PIN first in Profile → Payment PIN');
      return;
    }

    final pin = await promptPaymentPin(
      context,
      title: 'Confirm withdrawal',
      subtitle: 'Enter your 4-digit payment PIN to withdraw ${_money.format(amount)}',
    );
    if (pin == null || !mounted) return;

    setState(() => submitting = true);
    try {
      await store.requestWithdrawal(
        amount: amount,
        momoNumber: number,
        accountName: name,
        network: selectedNetwork,
        payoutType: payoutType,
        paymentPin: pin,
      );
      if (!mounted) return;
      amountCtrl.clear();
      _toast('Withdrawal requested. Usually processed within 15 minutes and sometimes instant.');
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
              'Request withdrawal',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
        children: [
          const Text('Check your payout details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            _isBank
                ? 'Money goes to this bank account. Wrong details can delay your payout.'
                : 'Money goes to this MoMo account. Wrong details can delay your payout.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
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
                    _PayoutMark(network: network, isBank: _isBank),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            payoutNetworkLabel(network),
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
                if (overview.feeFor(payoutType, amount) > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    overview.feeMode == 'percent'
                        ? 'Withdrawal fee ${overview.feePercent.toStringAsFixed(overview.feePercent % 1 == 0 ? 0 : 2)}% (${_money.format(overview.feeFor(payoutType, amount))})'
                        : 'Withdrawal fee ${_money.format(overview.feeFor(payoutType, amount))}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(
                    'Total deducted ${_money.format(amount + overview.feeFor(payoutType, amount))}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  overview.autoPaystack
                      ? 'Paystack will send this payout automatically.'
                      : 'Usually processed within 15 minutes and sometimes instant.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    final banks = overview.banks.isNotEmpty ? overview.banks : ghanaBanks;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          _BalanceCard(
            available: overview.availableBalance,
            onWithdrawAll: tooSmall ? null : _withdrawAll,
          ),
          const SizedBox(height: 16),
          if (overview.hasPending) ...[
            const _Notice(
              icon: Icons.hourglass_top_rounded,
              title: 'Withdrawal in processing',
              body: 'Your earlier request is still being paid out (usually within 15 minutes). '
                  'You can submit another withdrawal with your remaining balance.',
            ),
            const SizedBox(height: 16),
          ],
          if (tooSmall)
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
                  '1. How should we pay you?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TypeChip(
                        label: 'Mobile Money',
                        selected: !_isBank,
                        onTap: () => _setPayoutType('momo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TypeChip(
                        label: 'Bank',
                        selected: _isBank,
                        onTap: () => _setPayoutType('bank'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!_isBank) ...[
                  const Text(
                    'Choose your network',
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
                ] else ...[
                  const Text(
                    'Choose your bank',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap to open the bank list, then pick with the circle on the left.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  BankSelectField(
                    banks: banks,
                    selectedId: banks.any((b) => b.id == network) ? network : banks.first.id,
                    onSelected: (bank) => setState(() => network = bank.id),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  '2. Where should the money go?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numberCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(_isBank ? r'[0-9]' : r'[0-9 +]')),
                  ],
                  decoration: InputDecoration(
                    labelText: _isBank ? 'Account number' : 'MoMo number',
                    hintText: _isBank ? 'Bank account number' : '0XX XXX XXXX',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Account name',
                    hintText: _isBank
                        ? 'Name registered on the bank account'
                        : 'Name registered on the MoMo number',
                    border: const OutlineInputBorder(),
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
                    helperText: () {
                      final typed = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      final fee = overview.feeFor(payoutType, typed);
                      final base = 'Minimum ${_money.format(overview.minimum)}'
                          ' · Available ${_money.format(overview.availableBalance)}';
                      if (overview.feeMode == 'percent' && overview.feePercent > 0) {
                        return '$base · ${overview.feePercent.toStringAsFixed(overview.feePercent % 1 == 0 ? 0 : 2)}% fee';
                      }
                      if (_isBank && overview.bankTiers.isNotEmpty && typed <= 0) {
                        return '$base · Bank fee by amount (below GH₵1,000 → GH₵10 · from GH₵1,000 → GH₵20)';
                      }
                      if (fee <= 0) return base;
                      return '$base · ${_isBank ? 'Bank' : 'MoMo'} fee ${_money.format(fee)}';
                    }(),
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
              _WithdrawalRow(
                item: item,
                onTap: () => _showWithdrawalDetails(context, item),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _PayoutMark extends StatelessWidget {
  const _PayoutMark({required this.network, required this.isBank});

  final String network;
  final bool isBank;

  @override
  Widget build(BuildContext context) {
    if (!isBank && !isGhanaBank(network)) {
      return MomoNetworkLogo(network: network, size: 38);
    }
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF7ED) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1.4,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
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
  const _WithdrawalRow({required this.item, required this.onTap});

  final WithdrawalItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (item.status) {
      'paid' => (const Color(0xFFECFDF5), const Color(0xFF047857)),
      'rejected' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C)),
      'processing' => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
      _ => (const Color(0xFFFFFBEB), const Color(0xFFB45309)),
    };
    final stamp = DateTime.tryParse(item.processedAt ?? item.createdAt ?? '')?.toLocal();
    final isBank = item.payoutType == 'bank' || isGhanaBank(item.network);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PayoutMark(network: item.network, isBank: isBank),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money.format(item.amount),
                        style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.accent),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'View details',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent),
                      ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                ],
              ),
              if ((item.rejectionReason ?? item.failureReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  (item.rejectionReason ?? item.failureReason)!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showWithdrawalDetails(BuildContext context, WithdrawalItem item) {
  final (fill, ink) = switch (item.status) {
    'paid' => (const Color(0xFFECFDF5), const Color(0xFF047857)),
    'rejected' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C)),
    'processing' => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
    _ => (const Color(0xFFFFFBEB), const Color(0xFFB45309)),
  };
  final requested = DateTime.tryParse(item.createdAt ?? '')?.toLocal();
  final processed = DateTime.tryParse(item.processedAt ?? '')?.toLocal();
  final isBank = item.payoutType == 'bank' || isGhanaBank(item.network);
  final accountLabel = isBank ? 'Account number' : 'MoMo number';
  final channel = (item.payoutChannelLabel ?? '').trim().isNotEmpty
      ? item.payoutChannelLabel!
      : (isBank ? 'Bank transfer' : 'Mobile Money');
  final reference = (item.reference ?? '').trim().isNotEmpty ? item.reference! : 'WD-${item.id}';
  final proof = ApiConfig.resolveMediaUrl(item.proofUrl);

  return showAppSheet(
    context: context,
    builder: (ctx) => SheetShell(
      action: FilledButton(
        onPressed: () => Navigator.pop(ctx),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      children: [
        Row(
          children: [
            _PayoutMark(network: item.network, isBank: isBank),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Withdrawal details',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
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
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF9A3412)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _money.format(item.amount),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${item.networkLabel} · ${item.momoNumber}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13),
              ),
              if (item.accountName.trim().isNotEmpty)
                Text(
                  item.accountName,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _DetailTile(label: 'Reference', value: reference),
        _DetailTile(label: 'Payout to', value: '$accountLabel · ${item.momoNumber}'),
        _DetailTile(label: 'Account name', value: item.accountName.trim().isEmpty ? '—' : item.accountName),
        _DetailTile(label: 'Network / bank', value: item.networkLabel),
        _DetailTile(label: 'Payout channel', value: channel),
        _DetailTile(label: 'Amount', value: _money.format(item.amount)),
        if (item.fee > 0) _DetailTile(label: 'Fee', value: _money.format(item.fee)),
        if (item.fee > 0) _DetailTile(label: 'Total debited', value: _money.format(item.debited)),
        _DetailTile(
          label: 'Requested',
          value: requested == null ? '—' : _stamp.format(requested),
        ),
        _DetailTile(
          label: 'Processed',
          value: processed == null ? '—' : _stamp.format(processed),
        ),
        if ((item.adminNotes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _NoteBox(
            title: 'Admin note',
            body: item.adminNotes!.trim(),
            color: const Color(0xFFECFDF5),
            border: const Color(0xFFA7F3D0),
            ink: const Color(0xFF065F46),
          ),
        ],
        if ((item.rejectionReason ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _NoteBox(
            title: 'Rejection reason',
            body: item.rejectionReason!.trim(),
            color: const Color(0xFFFEF2F2),
            border: const Color(0xFFFECACA),
            ink: const Color(0xFF991B1B),
          ),
        ],
        if ((item.failureReason ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _NoteBox(
            title: 'Failure reason',
            body: item.failureReason!.trim(),
            color: const Color(0xFFFFFBEB),
            border: const Color(0xFFFDE68A),
            ink: const Color(0xFF92400E),
          ),
        ],
        if (proof.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.tryParse(proof);
              if (uri == null) return;
              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open payout proof')),
                );
              }
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('View / download payout proof'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: Color(0xFFFDBA74)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ],
    ),
  );
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  const _NoteBox({
    required this.title,
    required this.body,
    required this.color,
    required this.border,
    required this.ink,
  });

  final String title;
  final String body;
  final Color color;
  final Color border;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: ink, fontSize: 13)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: ink, height: 1.35, fontSize: 13)),
        ],
      ),
    );
  }
}
