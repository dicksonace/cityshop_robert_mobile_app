import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _stamp = DateFormat('d MMM yyyy, h:mm a');

/// RMB-wallet style awaiting / success / rejected screen for a manual deposit.
class ManualDepositStatusScreen extends StatefulWidget {
  const ManualDepositStatusScreen({super.key, required this.depositId});

  final int depositId;

  @override
  State<ManualDepositStatusScreen> createState() => _ManualDepositStatusScreenState();
}

class _ManualDepositStatusScreenState extends State<ManualDepositStatusScreen> {
  Map<String, dynamic>? item;
  String? error;
  bool loading = true;
  bool cancelling = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _poll?.cancel();
    final status = '${item?['status'] ?? ''}';
    if (status != 'pending') return;
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  Future<void> _load({bool initial = false}) async {
    if (initial) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await context.read<AppStore>().fetchManualTopUp(widget.depositId);
      if (!mounted) return;
      setState(() {
        item = data;
        loading = false;
        error = null;
      });
      _schedulePoll();
      if (data['status'] == 'approved') {
        unawaited(context.read<AppStore>().loadWallet());
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

  Future<void> _cancel() async {
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
    setState(() => cancelling = true);
    try {
      final data = await context.read<AppStore>().cancelManualTopUp(widget.depositId);
      if (!mounted) return;
      setState(() {
        item = data;
        cancelling = false;
      });
      _schedulePoll();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _when(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return _stamp.format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading && item == null) {
      return const Scaffold(body: FullPageLoader(label: 'Loading deposit…'));
    }
    if (error != null && item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Deposit status')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => _load(initial: true), child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final status = '${item?['status'] ?? 'pending'}';
    final pending = status == 'pending';
    final approved = status == 'approved';
    final amount = (item?['amount'] as num?)?.toDouble() ?? 0;
    final headerColor = approved
        ? const Color(0xFF16A34A)
        : (status == 'rejected' || status == 'cancelled')
            ? const Color(0xFFDC2626)
            : const Color(0xFF16A34A);
    final title = pending
        ? 'Awaiting Approval'
        : approved
            ? 'Deposit Credited'
            : status == 'cancelled'
                ? 'Request Cancelled'
                : 'Deposit Rejected';
    final subtitle = pending
        ? 'Your deposit is being reviewed.'
        : approved
            ? 'Funds have been added to your wallet.'
            : '${item?['admin_notes'] ?? 'This request was not credited.'}';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: headerColor,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                children: [
                  if (pending)
                    const SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    )
                  else
                    Icon(
                      approved ? Icons.check_circle : Icons.cancel,
                      color: Colors.white,
                      size: 56,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  _row('Deposit Amount', _money.format(amount)),
                  _row('Type', 'Manual (MoMo)'),
                  _row('Date/Time', _when('${item?['created_at'] ?? ''}')),
                  _row(
                    'Status',
                    status == 'pending' ? 'Pending' : status,
                    badge: true,
                    pending: pending,
                    approved: approved,
                  ),
                  if ('${item?['payment_reference'] ?? ''}'.isNotEmpty)
                    _row('Reference', '${item?['payment_reference']}'),
                  if (pending) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Checking for updates automatically…\nYou can also leave or come back later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () => context.go('/shop?tab=wallet'),
                          child: const Text('Back to Wallet', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: () => context.go('/wallet/manual-deposit'),
                          child: const Text('View History', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                  if (pending) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: cancelling ? null : _cancel,
                      child: Text(cancelling ? 'Cancelling…' : 'Cancel request'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool badge = false, bool pending = false, bool approved = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
          if (badge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: pending
                    ? const Color(0xFFFEF3C7)
                    : approved
                        ? const Color(0xFFD1FAE5)
                        : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: pending
                      ? const Color(0xFF92400E)
                      : approved
                          ? const Color(0xFF065F46)
                          : const Color(0xFF991B1B),
                ),
              ),
            )
          else
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
