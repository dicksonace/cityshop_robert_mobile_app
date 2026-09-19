import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _when = DateFormat('MMM d, yyyy, h:mm a');

class WithdrawalStatusScreen extends StatefulWidget {
  const WithdrawalStatusScreen({super.key, required this.id, this.initial});

  final int id;
  final WithdrawalItem? initial;

  @override
  State<WithdrawalStatusScreen> createState() => _WithdrawalStatusScreenState();
}

class _WithdrawalStatusScreenState extends State<WithdrawalStatusScreen> {
  WithdrawalItem? item;
  bool loading = true;
  bool refreshing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    item = widget.initial;
    loading = widget.initial == null;
    _load();
    Future<void>.delayed(const Duration(seconds: 8), _poll);
  }

  Future<void> _poll() async {
    if (!mounted) return;
    if (item?.isOpen == true) {
      await _load();
      if (mounted && item?.isOpen == true) {
        Future<void>.delayed(const Duration(seconds: 8), _poll);
      }
    }
  }

  Future<void> _load() async {
    try {
      final next = await context.read<AppStore>().loadWithdrawal(widget.id);
      if (!mounted) return;
      setState(() {
        item = next;
        loading = false;
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    await _load();
    if (mounted) setState(() => refreshing = false);
  }

  Map<String, dynamic> _presentation(WithdrawalItem current) {
    final raw = current.statusPresentation;
    if (raw != null && raw.isNotEmpty) return raw;
    return switch (current.status) {
      'paid' => {
          'header_title': 'Payout Complete!',
          'header_subtitle': 'GHS has been sent to your payout account',
          'header_color': '#22c55e',
          'badge_label': 'Completed',
        },
      'rejected' => {
          'header_title': 'Withdrawal Rejected',
          'header_subtitle': 'See details below',
          'header_color': '#dc2626',
          'badge_label': 'Rejected',
        },
      _ => {
          'header_title': 'Processing',
          'header_subtitle': 'Your withdrawal is being sent',
          'header_color': '#ef4444',
          'badge_label': 'Processing',
        },
    };
  }

  Color _hex(String hex, {Color fallback = const Color(0xFFEF4444)}) {
    final value = hex.replaceAll('#', '');
    if (value.length != 6) return fallback;
    return Color(int.parse('FF$value', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final current = item;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Withdrawal'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: refreshing ? null : _refresh,
            icon: refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading && current == null
          ? const Center(child: CircularProgressIndicator())
          : current == null
              ? Center(child: Text(error ?? 'Withdrawal not found'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Material(
                      color: Colors.white,
                      elevation: 8,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(current),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _summary(current),
                                const SizedBox(height: 14),
                                _payout(current),
                                const SizedBox(height: 14),
                                _details(current),
                                if ((current.rejectionReason ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  _note(current.rejectionReason!, color: const Color(0xFFFEF2F2), ink: const Color(0xFFB91C1C)),
                                ],
                                if (current.isPaid) ...[
                                  const SizedBox(height: 14),
                                  _note(
                                    '${_money.format(current.amount)} was sent to your ${current.networkLabel} account.',
                                    color: const Color(0xFFECFDF5),
                                    ink: const Color(0xFF047857),
                                  ),
                                ],
                                if (current.proofUrl != null && current.proofUrl!.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      ApiConfig.resolveMediaUrl(current.proofUrl!),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                    ),
                                  ),
                                ],
                                if (current.isOpen) ...[
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Status updates automatically. Tap Refresh or return to your wallet anytime.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: refreshing ? null : _refresh,
                                        child: Text(refreshing ? 'Refreshing…' : 'Refresh'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => context.go('/shop?tab=wallet'),
                                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                                        child: const Text('Back to Wallet'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _header(WithdrawalItem current) {
    final presentation = _presentation(current);
    final color = _hex('${presentation['header_color']}');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      color: color,
      child: Column(
        children: [
          if (current.isPaid)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 48),
            )
          else if (current.isRejected)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.cancel, color: Colors.white, size: 48),
            )
          else
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white),
            ),
          const SizedBox(height: 16),
          Text(
            '${presentation['header_title'] ?? 'Processing'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
          ),
          const SizedBox(height: 6),
          Text(
            '${presentation['header_subtitle'] ?? 'Your withdrawal is being sent'}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _summary(WithdrawalItem current) {
    final isBank = current.payoutType == 'bank';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'WITHDRAWAL SUMMARY',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF6B7280), letterSpacing: 0.7),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOU RECEIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _money.format(current.amount),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.05),
                ),
                const SizedBox(height: 4),
                Text(
                  isBank ? 'GHS to your bank' : 'GHS to your MoMo',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          if (current.fee > 0) ...[
            const SizedBox(height: 14),
            _row('Fee', _money.format(current.fee), valueColor: const Color(0xFFDC2626), bold: true),
            const SizedBox(height: 8),
            _row('Total debited', _money.format(current.debited)),
          ],
        ],
      ),
    );
  }

  Widget _payout(WithdrawalItem current) {
    final isBank = current.payoutType == 'bank';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCFCE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYOUT ACCOUNT (${isBank ? 'BANK' : 'MOMO'})',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF166534), letterSpacing: 0.6),
          ),
          const SizedBox(height: 10),
          _row('Network', current.networkLabel),
          const SizedBox(height: 8),
          _row('Number', current.momoNumber),
          const SizedBox(height: 8),
          _row('Account Name', current.accountName.isEmpty ? '—' : current.accountName),
        ],
      ),
    );
  }

  Widget _details(WithdrawalItem current) {
    final presentation = _presentation(current);
    final submitted = DateTime.tryParse(current.createdAt ?? '')?.toLocal();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          _row('Reference', current.reference ?? 'WITHDRAWAL-${current.id}'),
          const SizedBox(height: 8),
          _row('Request ID', '#${current.id}'),
          const SizedBox(height: 8),
          _row('Submitted', submitted == null ? '—' : _when.format(submitted)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Status', style: TextStyle(color: Color(0xFF6B7280), fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: current.isPaid
                      ? const Color(0xFFD1FAE5)
                      : current.isRejected
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${presentation['badge_label'] ?? current.statusLabel}',
                  style: TextStyle(
                    color: current.isPaid
                        ? const Color(0xFF047857)
                        : current.isRejected
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF92400E),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor, bool bold = false}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 14))),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF1F2937),
              fontSize: 14,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _note(String body, {required Color color, required Color ink}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: ink, width: 4)),
      ),
      child: Text(body, style: TextStyle(color: ink, height: 1.35)),
    );
  }
}
