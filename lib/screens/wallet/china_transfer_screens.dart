import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';

final _ghs = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);
final _transferStamp = DateFormat('d MMM yyyy, h:mm a');

String _formatTransferWhen(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  try {
    return _transferStamp.format(DateTime.parse(raw).toLocal());
  } catch (_) {
    return raw;
  }
}

void _popToChinaRmbHub(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/wallet/china-rmb');
  }
}

bool _isBuyerQrField(Map<String, dynamic> field) {
  if ((field['file_url'] as String? ?? '').trim().isEmpty) return false;
  final type = (field['type'] as String? ?? '').toLowerCase();
  final blob = '${field['name'] ?? ''} ${field['label'] ?? ''}'.toLowerCase();
  return ['image', 'document', 'files'].contains(type) || blob.contains('qr');
}

bool _transferIsTerminal(String? status) {
  return [
    'completed',
    'cancelled',
    'payment_rejected',
    'transfer_failed',
    'refunded',
  ].contains(status);
}

String _formatBuyRate(double n) {
  if (n <= 0) return '—';
  return n.toStringAsFixed(3);
}

/// Use the same 3-decimal rate for math as we show buyers (avoids 71,000×0.561 ≠ 39,831.71 drift).
double _buyRateForCalculation(double rmbPerGhs) {
  if (rmbPerGhs <= 0) return 0;
  return double.parse(_formatBuyRate(rmbPerGhs));
}

String _formatRmbAmount(double n) {
  if (n <= 0) return '';
  return n.toStringAsFixed(2);
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _optionalRecipientLabel(Map<String, dynamic> field) {
  final name = (field['name'] as String? ?? '').toLowerCase();
  if (name.contains('alipay') || name.contains('account')) return 'Alipay Account';
  if (name.contains('name')) return 'Recipient Name';
  if (name.contains('note')) return 'Notes';
  final label = (field['label'] as String? ?? 'Field').trim();
  return label.replaceAll(RegExp(r'\s*\*$'), '');
}

String _optionalRecipientHint(Map<String, dynamic> field) {
  final name = (field['name'] as String? ?? '').toLowerCase();
  if (name.contains('alipay') || name.contains('account')) return "Recipient's Alipay ID";
  if (name.contains('name')) return 'Name of recipient';
  if (name.contains('note')) return 'Any additional information';
  return (field['placeholder'] as String?) ?? '';
}

class BuyRmbClosedBanner extends StatelessWidget {
  const BuyRmbClosedBanner({super.key, required this.transferHours, this.compact = false});

  final Map<String, dynamic>? transferHours;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hours = transferHours;
    if (hours == null || hours['configured'] != true || hours['is_open_now'] == true) {
      return const SizedBox.shrink();
    }

    final message = (hours['closed_message'] as String?)?.trim().isNotEmpty == true
        ? '${hours['closed_message']}'
        : "Sorry, we're closed. We continue when we reopen.";
    final openLabel = hours['open_time_label'] as String?;
    final closeLabel = hours['close_time_label'] as String?;

    return Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEDD5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.schedule_rounded, color: const Color(0xFFB45309), size: compact ? 16 : 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : 14,
                    color: const Color(0xFF78350F),
                    height: 1.35,
                  ),
                ),
                if (openLabel != null || closeLabel != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Transfer time',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                  ),
                  if (openLabel != null)
                    Text(
                      'Open time $openLabel',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                    ),
                  if (closeLabel != null)
                    Text(
                      'Close time $closeLabel',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyRmbLiveStatusChip extends StatelessWidget {
  const _BuyRmbLiveStatusChip({required this.live, required this.serviceEnabled});

  final bool live;
  final bool serviceEnabled;

  @override
  Widget build(BuildContext context) {
    if (!serviceEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_outline, size: 16, color: Color(0xFF6B7280)),
            SizedBox(width: 6),
            Text('Paused', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF374151))),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: live ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: live ? const Color(0xFFA7F3D0) : const Color(0xFFFED7AA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: live ? const Color(0xFF059669) : const Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            live ? 'Live' : 'Paused',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: live ? const Color(0xFF065F46) : const Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }
}

/// Buy RMB calculator: Today's Rate, You send / They receive, arrival, Continue.
class BuyRmbCalculatorCard extends StatefulWidget {
  const BuyRmbCalculatorCard({
    super.key,
    required this.ghsPerRmb,
    required this.rmbPerGhs,
    required this.feeMode,
    required this.feeValue,
    required this.enabled,
    this.transferHours,
    this.instructions,
    this.initialGhs,
    required this.onContinue,
  });

  final double ghsPerRmb;
  final double rmbPerGhs;
  final String feeMode;
  final double feeValue;
  final bool enabled;
  final Map<String, dynamic>? transferHours;
  final String? instructions;
  final String? initialGhs;
  final void Function(String ghsAmount) onContinue;

  @override
  State<BuyRmbCalculatorCard> createState() => _BuyRmbCalculatorCardState();
}

class _BuyRmbCalculatorCardState extends State<BuyRmbCalculatorCard> {
  late final TextEditingController ghs;
  late final TextEditingController cny;
  bool syncing = false;

  double get calcRate => _buyRateForCalculation(widget.rmbPerGhs);

  @override
  void initState() {
    super.initState();
    final start = widget.initialGhs?.trim() ?? '';
    ghs = TextEditingController(text: start);
    final send = double.tryParse(start) ?? 0;
    cny = TextEditingController(
      text: send > 0 && calcRate > 0 ? _formatRmbAmount(send * calcRate) : '',
    );
  }

  @override
  void dispose() {
    ghs.dispose();
    cny.dispose();
    super.dispose();
  }

  void _fromGhs(String raw) {
    if (syncing) return;
    syncing = true;
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned != raw) {
      ghs.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    final send = double.tryParse(cleaned) ?? 0;
    if (send > 0 && calcRate > 0) {
      cny.text = _formatRmbAmount(send * calcRate);
    } else {
      cny.text = '';
    }
    syncing = false;
    setState(() {});
  }

  void _fromCny(String raw) {
    if (syncing) return;
    syncing = true;
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned != raw) {
      cny.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    final receive = double.tryParse(cleaned) ?? 0;
    if (receive > 0 && calcRate > 0) {
      ghs.text = (receive / calcRate).toStringAsFixed(2);
    } else {
      ghs.text = '';
    }
    syncing = false;
    setState(() {});
  }

  double get send => double.tryParse(ghs.text) ?? 0;
  double get receive => calcRate > 0 && send > 0 ? send * calcRate : 0;
  double get fee =>
      widget.feeMode == 'percent' ? send * widget.feeValue / 100 : widget.feeValue;
  bool get canContinue => widget.enabled && send > 0;

  bool get hoursOpen {
    final hours = widget.transferHours;
    if (hours == null || hours['configured'] != true) return true;
    return hours['is_open_now'] == true;
  }

  bool get isLiveNow => widget.enabled && hoursOpen;

  String get continueLabel {
    if (!widget.enabled) return 'Transfers paused';
    if (!hoursOpen) return 'Continue anyway';
    return 'Continue';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF5B21B6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF7C3AED), width: 1.5),
            ),
            child: Column(
              children: [
                const Text(
                  'GHS to RMB',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1 GHS → ${_formatBuyRate(calcRate)} RMB',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 0.2,
                  ),
                ),
                if (calcRate > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Current rate: ${_formatBuyRate(calcRate)} RMB',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('Amount in GHS (GH₵)', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563))),
          const SizedBox(height: 8),
          _AmountField(
            symbol: '₵',
            code: 'GHS',
            controller: ghs,
            onChanged: _fromGhs,
          ),
          const SizedBox(height: 14),
          const Text('RMB equivalent (¥)', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563))),
          const SizedBox(height: 8),
          _AmountField(
            symbol: '¥',
            code: 'CNY',
            controller: cny,
            onChanged: _fromCny,
          ),
          if (fee > 0 && send > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Fee ${_ghs.format(fee)} · Total ${_ghs.format(send + fee)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            hoursOpen ? 'Arrives in 5–30 minutes' : 'Orders outside hours are queued for the next open window.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: hoursOpen ? const Color(0xFF059669) : const Color(0xFFB45309),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _BuyRmbLiveStatusChip(live: isLiveNow, serviceEnabled: widget.enabled),
              const Spacer(),
              if (widget.transferHours?['open_time_label'] != null &&
                  widget.transferHours?['close_time_label'] != null)
                Text(
                  '${widget.transferHours!['open_time_label']} – ${widget.transferHours!['close_time_label']}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
                ),
            ],
          ),
          if (!hoursOpen && widget.enabled) ...[
            const SizedBox(height: 12),
            BuyRmbClosedBanner(transferHours: widget.transferHours, compact: true),
          ],
          if (!widget.enabled) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Text(
                'Buy RMB is temporarily paused by admin. You can still check the rate, but new transfers are not accepted right now.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4B5563), height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: canContinue ? () => widget.onContinue(send.toStringAsFixed(2)) : null,
              style: FilledButton.styleFrom(
                backgroundColor: isLiveNow ? const Color(0xFF6366F1) : const Color(0xFFF59E0B),
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(
                continueLabel,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
          if (canContinue && !hoursOpen) ...[
            const SizedBox(height: 8),
            Text(
              'You can still submit — we process when transfer hours reopen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountField extends StatefulWidget {
  const _AmountField({
    required this.symbol,
    required this.code,
    required this.controller,
    required this.onChanged,
  });

  final String symbol;
  final String code;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: focused ? Colors.white : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: focused ? const Color(0xFF6366F1) : const Color(0xFFE5E7EB),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(
              widget.symbol,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: widget.onChanged,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                // Avoid ListView centering the focused field (looks like the page is
                // split in half with a blank region under Continue).
                scrollPadding: const EdgeInsets.only(bottom: 24),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '0.00',
                  hintStyle: TextStyle(color: Color(0xFFD1D5DB), fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.code,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF4B5563)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTransferListDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  try {
    final dt = DateTime.parse(raw).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Today · ${DateFormat('h:mm a').format(dt)}';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(dt);
  } catch (_) {
    return raw;
  }
}

class _BuyRmbTransferStatusStyle {
  const _BuyRmbTransferStatusStyle({
    required this.label,
    required this.color,
    required this.background,
    required this.border,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final Color border;
  final IconData icon;
}

_BuyRmbTransferStatusStyle _buyRmbTransferStatusStyle(Map<String, dynamic> item) {
  final status = '${item['status'] ?? ''}';
  final label = '${item['status_label'] ?? status}';
  switch (status) {
    case 'completed':
      return _BuyRmbTransferStatusStyle(
        label: label,
        color: const Color(0xFF047857),
        background: const Color(0xFFD1FAE5),
        border: const Color(0xFFA7F3D0),
        icon: Icons.check_circle_rounded,
      );
    case 'processing':
    case 'payment_verification':
    case 'payment_submitted':
      return _BuyRmbTransferStatusStyle(
        label: label,
        color: const Color(0xFF6D28D9),
        background: const Color(0xFFEDE9FE),
        border: const Color(0xFFDDD6FE),
        icon: Icons.hourglass_top_rounded,
      );
    case 'rmb_sent':
      return _BuyRmbTransferStatusStyle(
        label: label,
        color: const Color(0xFF047857),
        background: const Color(0xFFD1FAE5),
        border: const Color(0xFFA7F3D0),
        icon: Icons.check_circle_rounded,
      );
    case 'pending_payment':
      return _BuyRmbTransferStatusStyle(
        label: label,
        color: const Color(0xFFB45309),
        background: const Color(0xFFFFEDD5),
        border: const Color(0xFFFED7AA),
        icon: Icons.schedule_rounded,
      );
    case 'cancelled':
    case 'payment_rejected':
    case 'transfer_failed':
    case 'refunded':
      return _BuyRmbTransferStatusStyle(
        label: label,
        color: const Color(0xFFB91C1C),
        background: const Color(0xFFFEE2E2),
        border: const Color(0xFFFECACA),
        icon: Icons.cancel_rounded,
      );
    default:
      return _BuyRmbTransferStatusStyle(
        label: label,
        color: AppColors.primary,
        background: AppColors.ringOrange,
        border: const Color(0xFFFED7AA),
        icon: Icons.sync_rounded,
      );
  }
}

class BuyRmbRecentTransferTile extends StatelessWidget {
  const BuyRmbRecentTransferTile({
    super.key,
    required this.item,
    required this.onTap,
    this.sellFlow = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool sellFlow;

  @override
  Widget build(BuildContext context) {
    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : <String, dynamic>{};
    final ghs = (quote['total_payable_ghs'] as num?)?.toDouble() ?? 0;
    final rmb = (quote['rmb_amount'] as num?)?.toDouble() ?? 0;
    final payoutCurrency = quote['payout_currency']?.toString() ?? 'ghs';
    final ghsPayout = (quote['ghs_payout'] as num?)?.toDouble() ?? 0;
    final usdPayout = (quote['usd_payout'] as num?)?.toDouble() ?? 0;
    final reference = '${item['reference'] ?? 'Transfer'}';
    final when = _formatTransferListDate(item['created_at'] as String?);
    final status = _buyRmbTransferStatusStyle(item);
    final payoutLabel = payoutCurrency == 'ghs'
        ? _ghs.format(ghsPayout)
        : '\$${usdPayout.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: sellFlow
                            ? const [Color(0xFF059669), Color(0xFF047857)]
                            : const [Color(0xFF7C3AED), Color(0xFF5B21B6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      sellFlow ? Icons.south_west_rounded : Icons.currency_exchange_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reference,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.1),
                        ),
                        if (when.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            when,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (sellFlow) ...[
                              Text(
                                '¥${rmb.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF047857)),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF9CA3AF)),
                              ),
                              Text(
                                payoutLabel,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF111827)),
                              ),
                            ] else ...[
                              Text(
                                _ghs.format(ghs),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF111827)),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF9CA3AF)),
                              ),
                              Text(
                                '¥${rmb.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF5B21B6)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: status.background,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: status.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(status.icon, size: 13, color: status.color),
                            const SizedBox(width: 4),
                            Text(
                              status.label,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: status.color),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF), size: 22),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BuyRmbRecentTransfersSection extends StatelessWidget {
  const BuyRmbRecentTransfersSection({
    super.key,
    required this.transfers,
    required this.onTransferTap,
    this.title = 'Recent transfers',
    this.sellFlowFor,
    this.showAutoRefresh = false,
  });

  final List<Map<String, dynamic>> transfers;
  final void Function(Map<String, dynamic> item) onTransferTap;
  final String title;
  final bool Function(Map<String, dynamic> item)? sellFlowFor;
  final bool showAutoRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, size: 20, color: Color(0xFF5B21B6)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const Spacer(),
            if (showAutoRefresh)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    SizedBox(width: 5),
                    Text('Live', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8))),
                  ],
                ),
              ),
            if (transfers.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${transfers.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF6D28D9)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (transfers.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF7C3AED), size: 28),
                ),
                const SizedBox(height: 14),
                const Text(
                  'No transfers yet',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your Buy RMB history will show up here after your first transfer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, height: 1.4, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...transfers.map(
            (item) => BuyRmbRecentTransferTile(
              item: item,
              sellFlow: sellFlowFor?.call(item) ?? false,
              onTap: () => onTransferTap(item),
            ),
          ),
      ],
    );
  }
}

class ChinaTransferHubScreen extends StatefulWidget {
  const ChinaTransferHubScreen({super.key});

  @override
  State<ChinaTransferHubScreen> createState() => _ChinaTransferHubScreenState();
}

class _ChinaTransferHubScreenState extends State<ChinaTransferHubScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> config = {};
  List<Map<String, dynamic>> transfers = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await context.read<AppStore>().loadChinaTransfers();
      if (!mounted) return;
      setState(() {
        config = Map<String, dynamic>.from(data['config'] as Map? ?? {});
        transfers = (data['transfers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        loading = false;
        error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) error = e.toString();
        loading = false;
      });
    }
  }

  Map<String, dynamic>? get rate =>
      config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;

  @override
  Widget build(BuildContext context) {
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? 0;
    final rmbPerGhs = (rate?['rmb_per_ghs'] as num?)?.toDouble() ??
        (ghsPerRmb > 0 ? 1 / ghsPerRmb : 0);
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    final enabled = config['enabled'] == true;
    final minGhs = (rate?['min_ghs'] as num?)?.toDouble();
    final transferHours =
        config['transfer_hours'] is Map ? Map<String, dynamic>.from(config['transfer_hours'] as Map) : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popToChinaRmbHub(context);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => _popToChinaRmbHub(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Buy RMB'),
        actions: [
          if (!loading)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text('Auto refresh', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _load(),
          ),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading rates…')
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                  children: [
                    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                    Text(
                      'Send GHS, receive CNY in China via Alipay.',
                      style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    if (rate != null)
                      BuyRmbCalculatorCard(
                        ghsPerRmb: ghsPerRmb,
                        rmbPerGhs: rmbPerGhs,
                        feeMode: feeMode,
                        feeValue: feeValue,
                        enabled: enabled,
                        transferHours: transferHours,
                        instructions: config['instructions'] as String?,
                        initialGhs: minGhs != null && minGhs > 0 ? minGhs.toStringAsFixed(0) : null,
                        onContinue: (amount) async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          await context.push('/wallet/china-transfer/create', extra: amount);
                          if (mounted) _load(silent: true);
                        },
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFD1D5DB), style: BorderStyle.solid),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'Rate not published yet',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'China transfers will open here once admin publishes a rate.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),
                    BuyRmbRecentTransfersSection(
                      transfers: transfers,
                      showAutoRefresh: true,
                      onTransferTap: (item) async {
                        await context.push('/wallet/china-transfer/${item['id']}');
                        if (mounted) _load(silent: true);
                      },
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class ChinaTransferCreateScreen extends StatefulWidget {
  const ChinaTransferCreateScreen({super.key, this.initialGhs});

  final String? initialGhs;

  @override
  State<ChinaTransferCreateScreen> createState() => _ChinaTransferCreateScreenState();
}

class _ChinaTransferCreateScreenState extends State<ChinaTransferCreateScreen> {
  Map<String, dynamic> config = {};
  bool loading = true;
  bool submitting = false;
  String? error;
  final amount = TextEditingController();
  final values = <int, String>{};
  final files = <int, XFile>{};

  @override
  void initState() {
    super.initState();
    amount.text = widget.initialGhs ?? '1000';
    _load();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final store = context.read<AppStore>();
      await store.loadWallet();
      final data = await store.loadChinaTransfers();
      if (!mounted) return;
      final cfg = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      setState(() {
        config = cfg;
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

  List<Map<String, dynamic>> get fields => (config['fields'] as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  List<Map<String, dynamic>> get recipientFields => fields.where((f) {
        final g = (f['group'] as String? ?? '').toLowerCase();
        return !['payment', 'payment_proof', 'proof'].contains(g);
      }).toList();

  bool _isQrField(Map<String, dynamic> field) {
    final type = field['type'] as String? ?? 'text';
    final blob = '${field['name'] ?? ''} ${field['label'] ?? ''}'.toLowerCase();
    return ['image', 'document', 'files'].contains(type) || blob.contains('qr');
  }

  List<Map<String, dynamic>> get qrFields => recipientFields.where(_isQrField).toList();
  List<Map<String, dynamic>> get textRecipientFields => recipientFields
      .where((f) => !_isQrField(f))
      .where((f) {
        final name = (f['name'] as String? ?? '').toLowerCase();
        // Hide phone / address — rmb-wallet only shows account, name, notes.
        return !name.contains('phone') && name != 'recipient_address';
      })
      .toList();

  Future<void> _submit() async {
    final store = context.read<AppStore>();
    if (!(store.user?.canStoreWalletFunds ?? false)) {
      setState(() => error = 'Approve your Ghana Card (KYC) before transferring.');
      return;
    }
    if (!(store.user?.hasPaymentPin ?? false)) {
      setState(() => error = 'Set a 4-digit payment PIN in Profile first.');
      return;
    }

    final pin = await promptPaymentPin(
      context,
      title: 'Confirm Alipay transfer',
      subtitle: 'Authorize this transfer with your payment PIN',
    );
    if (pin == null || !mounted) return;

    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final created = await store.submitChinaTransfer(
            fundingSource: 'ghs_wallet',
            ghsAmount: amount.text,
            paymentMethodId: null,
            paymentPin: pin,
            fields: values,
            files: files,
          );
      if (!mounted) return;
      context.go('/wallet/china-transfer/${created['id']}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final kycOk = store.user?.canStoreWalletFunds ?? false;
    final hasPin = store.user?.hasPaymentPin ?? false;
    final rate = config['rate'] is Map ? Map<String, dynamic>.from(config['rate'] as Map) : null;
    final ghsPerRmb = (rate?['ghs_per_rmb'] as num?)?.toDouble() ?? 0;
    final rmbPerGhs = _buyRateForCalculation(
      (rate?['rmb_per_ghs'] as num?)?.toDouble() ?? (ghsPerRmb > 0 ? 1 / ghsPerRmb : 0),
    );
    final send = double.tryParse(amount.text) ?? 0;
    final feeMode = rate?['fee_mode'] as String? ?? 'flat';
    final feeValue = (rate?['fee_value'] as num?)?.toDouble() ?? 0;
    // Same as rmb-wallet: RMB = GHS × (RMB per 1 GHS), using the 3-decimal displayed rate.
    final rmb = rmbPerGhs > 0 ? send * rmbPerGhs : 0.0;
    final fee = feeMode == 'percent' ? send * feeValue / 100 : feeValue;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _popToChinaRmbHub(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text('Submit Transfer Request'),
      ),
      resizeToAvoidBottomInset: true,
      body: loading
          ? const FullPageLoader(label: 'Loading form…')
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                if (!kycOk) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: Text('KYC required before transfer.', style: TextStyle(fontWeight: FontWeight.w600))),
                        TextButton(onPressed: () => context.push('/kyc'), child: const Text('Verify')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!hasPin) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Set a payment PIN in Profile first.', style: TextStyle(fontWeight: FontWeight.w600))),
                        TextButton(onPressed: () => context.push('/profile/payment-pin'), child: const Text('Set PIN')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('You send', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text(_ghs.format(send), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('They receive', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text('¥${rmb.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (rmbPerGhs > 0)
                        Text(
                          'Rate 1 GHS → ${_formatBuyRate(rmbPerGhs)} RMB',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4338CA)),
                        ),
                      if (rmbPerGhs > 0) const SizedBox(height: 4),
                      Text(
                        'Fee ${_ghs.format(fee)} · Total ${_ghs.format(send + fee)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF4338CA)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pay from wallet balance',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Available: ${_ghs.format(store.wallet?.availableBalance ?? 0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total debit: ${_ghs.format(send + fee)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF047857)),
                      ),
                      if ((store.wallet?.availableBalance ?? 0) + 0.0001 < send + fee) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.push('/wallet/manual-deposit'),
                          child: const Text('Top up wallet'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...qrFields.map((field) {
                  final id = (field['id'] as num).toInt();
                  final picked = files[id];
                  final required = field['required'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _AlipayQrUploadCard(
                      required: required,
                      helpText: (field['help_text'] as String?)?.isNotEmpty == true
                          ? '${field['help_text']}'
                          : 'Upload a clear Alipay receive QR',
                      file: picked,
                      onPick: () async {
                        final file = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (file != null) setState(() => files[id] = file);
                      },
                      onClear: picked == null
                          ? null
                          : () => setState(() => files.remove(id)),
                    ),
                  );
                }),
                ...textRecipientFields.map((field) {
                  final id = (field['id'] as num).toInt();
                  final type = field['type'] as String? ?? 'text';
                  // rmb-wallet: only QR is required — account / name / notes are optional.
                  final label = '${_optionalRecipientLabel(field)} (Optional)';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      onChanged: (v) => values[id] = v,
                      decoration: InputDecoration(
                        labelText: label,
                        hintText: _optionalRecipientHint(field),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: type == 'textarea' ? 3 : 1,
                    ),
                  );
                }),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    submitting ? 'Submitting…' : 'Submit Transfer Request',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

class ChinaTransferShowScreen extends StatefulWidget {
  const ChinaTransferShowScreen({super.key, required this.id});

  final int id;

  @override
  State<ChinaTransferShowScreen> createState() => _ChinaTransferShowScreenState();
}

class _ChinaTransferShowScreenState extends State<ChinaTransferShowScreen> {
  Map<String, dynamic>? transfer;
  String? error;
  bool saving = false;
  Timer? _pollTimer;
  final _receiptKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    final status = transfer?['status'] as String?;
    if (_transferIsTerminal(status)) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final data = await context.read<AppStore>().fetchChinaTransfer(widget.id);
      if (!mounted) return;
      setState(() {
        transfer = data;
        error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => error = e.toString());
    }
  }

  Future<void> _saveNetworkImage(String url, String filename) async {
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allow photo access to save images')),
        );
      }
      return;
    }
    final resolved = ApiConfig.resolveMediaUrl(url);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$filename';
    await Dio().download(resolved, path);
    await Gal.putImage(path, album: 'CityShop');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Photos')),
      );
    }
  }

  Future<void> _downloadReceipt(String reference) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow photo access to save your receipt')),
          );
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary = _receiptKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Receipt not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Could not encode receipt');
      final dir = await getTemporaryDirectory();
      final safeRef = reference.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final path = '${dir.path}/CityShop_RMB_$safeRef.png';
      await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await Gal.putImage(path, album: 'CityShop');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt saved to Photos')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save receipt: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _openImage(String url) {
    final resolved = ApiConfig.resolveMediaUrl(url);
    if (resolved.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: resolved,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = transfer;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/wallet/china-rmb'),
          ),
          title: const Text('Buy RMB'),
        ),
        body: error != null
            ? Center(child: Text(error!))
            : const FullPageLoader(label: 'Loading transfer…'),
      );
    }

    final quote = item['quote'] is Map ? Map<String, dynamic>.from(item['quote'] as Map) : <String, dynamic>{};
    final breakdown = quote['breakdown'] is Map ? Map<String, dynamic>.from(quote['breakdown'] as Map) : <String, dynamic>{};
    final timeline = (item['timeline'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final fields = (item['fields'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final qrFields = fields.where(_isBuyerQrField).toList();
    final textFields = fields.where((f) => !_isBuyerQrField(f)).where((f) {
      final group = (f['group'] as String? ?? '').toLowerCase();
      return !['payment', 'payment_proof', 'proof'].contains(group);
    }).toList();
    final proofs = (item['proofs'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((p) => p['type'] == 'rmb_sent')
        .toList();
    final walletReceipt = item['wallet_receipt'] is Map ? Map<String, dynamic>.from(item['wallet_receipt'] as Map) : null;
    final reference = '${item['reference'] ?? ''}';
    final status = '${item['status'] ?? ''}';
    final statusLabel = '${item['status_label'] ?? status}';
    final funding = '${item['funding_source'] ?? ''}';
    final terminal = _transferIsTerminal(status);
    final completed = status == 'completed';
    final rmbAmount = (quote['rmb_amount'] as num?)?.toDouble() ?? 0;
    final displayWhen = completed
        ? _formatTransferWhen(item['completed_at'] as String? ?? item['sent_at'] as String?)
        : _formatTransferWhen(item['created_at'] as String?);

    Color statusColor = AppColors.primary;
    Color statusBg = AppColors.ringOrange;
    if (completed) {
      statusColor = const Color(0xFF059669);
      statusBg = const Color(0xFFD1FAE5);
    } else if (terminal) {
      statusColor = AppColors.danger;
      statusBg = const Color(0xFFFEE2E2);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/wallet/china-rmb'),
        ),
        title: Text(reference),
        actions: [
          if (!terminal)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text('Auto refresh', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (!terminal)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your RMB transfer request is $statusLabel. Ref $reference',
                        style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            RepaintBoundary(
              key: _receiptKey,
              child: ColoredBox(
                color: AppColors.background,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BuyerTransferCard(
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
                                      funding == 'rmb_wallet'
                                          ? '¥${rmbAmount.toStringAsFixed(2)}'
                                          : '${breakdown['total'] ?? _ghs.format((quote['total_payable_ghs'] as num?)?.toDouble() ?? 0)}',
                                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '→ ¥${rmbAmount.toStringAsFixed(2)} to Alipay',
                                      style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          if ((item['funding_source_label'] as String?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${item['funding_source_label']}',
                              style: const TextStyle(color: AppColors.emerald, fontWeight: FontWeight.w700),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _BuyerReceiptRow('Reference', reference),
                          _BuyerReceiptRow('Date & time', displayWhen),
                          if (walletReceipt != null) ...[
                            if (funding == 'rmb_wallet') ...[
                              if (walletReceipt['rmb_before'] != null)
                                _BuyerReceiptRow(
                                  'RMB before',
                                  '¥${(walletReceipt['rmb_before'] as num).toDouble().toStringAsFixed(2)}',
                                ),
                              if (walletReceipt['rmb_after'] != null)
                                _BuyerReceiptRow(
                                  'RMB after',
                                  '¥${(walletReceipt['rmb_after'] as num).toDouble().toStringAsFixed(2)}',
                                ),
                            ] else ...[
                              if (walletReceipt['balance_before'] != null)
                                _BuyerReceiptRow(
                                  'GHS before',
                                  _ghs.format((walletReceipt['balance_before'] as num).toDouble()),
                                ),
                              if (walletReceipt['balance_after'] != null)
                                _BuyerReceiptRow(
                                  'GHS after',
                                  _ghs.format((walletReceipt['balance_after'] as num).toDouble()),
                                ),
                            ],
                          ],
                          _BuyerReceiptRow(
                            'Exchange rate',
                            breakdown['rate'] as String? ?? '1 RMB = GH₵${((quote['ghs_per_rmb'] as num?)?.toDouble() ?? 0).toStringAsFixed(4)}',
                          ),
                          if (funding != 'rmb_wallet')
                            _BuyerReceiptRow(
                              'Fee',
                              breakdown['fee'] as String? ?? _ghs.format((quote['fee_ghs'] as num?)?.toDouble() ?? 0),
                            ),
                        ],
                      ),
                    ),
                    _BuyerTransferCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Progress', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 10),
                          ...timeline.map((step) {
                            final current = step['current'] == true;
                            final done = step['done'] == true;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    current
                                        ? Icons.radio_button_checked
                                        : done
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                    size: 20,
                                    color: current
                                        ? AppColors.primary
                                        : done
                                            ? const Color(0xFF059669)
                                            : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${step['label']}',
                                      style: TextStyle(
                                        fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                                        color: current ? AppColors.textPrimary : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if ((item['rejection_reason'] as String?)?.isNotEmpty == true)
              _BuyerTransferCard(
                child: Text(
                  '${item['rejection_reason']}',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                ),
              ),
            ...qrFields.map((field) {
              final url = '${field['file_url']}';
              return _BuyerTransferCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Your Alipay QR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'QR code you submitted for this transfer.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _openImage(url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          color: const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.all(16),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: CachedNetworkImage(
                              imageUrl: ApiConfig.resolveMediaUrl(url),
                              fit: BoxFit.contain,
                              placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
                              errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 48),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _saveNetworkImage(url, 'buyer_qr_$reference.jpg'),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download QR'),
                    ),
                  ],
                ),
              );
            }),
            if (textFields.isNotEmpty)
              _BuyerTransferCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recipient details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 10),
                    ...textFields.map(
                      (field) => _BuyerReceiptRow('${field['label']}', '${field['value'] ?? '—'}'),
                    ),
                  ],
                ),
              ),
            if (proofs.isNotEmpty)
              _BuyerTransferCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Text('🧾', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 8),
                        Text('Payment proof', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (item['rmb_sent_amount'] != null)
                      _BuyerReceiptRow(
                        'RMB sent',
                        '¥${(item['rmb_sent_amount'] as num).toDouble().toStringAsFixed(2)}',
                      ),
                    if ((item['rmb_transfer_ref'] as String?)?.isNotEmpty == true)
                      _BuyerReceiptRow('Transfer ref', '${item['rmb_transfer_ref']}'),
                    if ((item['sent_at'] as String?)?.isNotEmpty == true)
                      _BuyerReceiptRow('Sent at', _formatTransferWhen(item['sent_at'] as String?)),
                    if (completed && (item['completed_at'] as String?)?.isNotEmpty == true)
                      _BuyerReceiptRow('Completed', _formatTransferWhen(item['completed_at'] as String?)),
                    const SizedBox(height: 10),
                    ...proofs.map((proof) {
                      final url = '${proof['url']}';
                      final name = '${proof['original_name'] ?? 'Proof'}';
                      final proofWhen = _formatTransferWhen(proof['created_at'] as String?);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (url.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => _openImage(url),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: CachedNetworkImage(
                                    imageUrl: ApiConfig.resolveMediaUrl(url),
                                    fit: BoxFit.contain,
                                    placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
                                    errorWidget: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (proofWhen != '—') Text(proofWhen, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: url.isEmpty
                                ? null
                                : () => _saveNetworkImage(url, 'rmb_proof_$reference.jpg'),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Download proof'),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            if (completed)
              FilledButton.icon(
                onPressed: saving ? null : () => _downloadReceipt(reference),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.receipt_long),
                label: Text(saving ? 'Saving…' : 'Download receipt'),
              ),
          ],
        ),
      ),
    );
  }
}

class _BuyerTransferCard extends StatelessWidget {
  const _BuyerTransferCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _BuyerReceiptRow extends StatelessWidget {
  const _BuyerReceiptRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Payment-proof style upload: green check + size + Change / X + preview.
class _AlipayQrUploadCard extends StatelessWidget {
  const _AlipayQrUploadCard({
    required this.required,
    required this.helpText,
    required this.file,
    required this.onPick,
    this.onClear,
  });

  final bool required;
  final String helpText;
  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  Future<void> _openPreview(BuildContext context) async {
    if (file == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.file(File(file!.path), fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = file != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Upload Alipay QR Code',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black),
              ),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFDC2626)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(helpText, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: picked ? const Color(0xFFECFDF5) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked ? const Color(0xFF6EE7B7) : const Color(0xFFD1D5DB),
              width: picked ? 1.6 : 1.2,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: picked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              FutureBuilder<int>(
                                future: file!.length(),
                                builder: (context, snap) {
                                  final size = snap.data;
                                  return Text(
                                    size == null ? '…' : _formatFileSize(size),
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: onPick,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Change', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        if (onClear != null) ...[
                          const SizedBox(width: 6),
                          Material(
                            color: const Color(0xFFDC2626),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onClear,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _openPreview(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(file!.path),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Click image to view full size',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                    ),
                  ],
                )
              : InkWell(
                  onTap: onPick,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Column(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 40, color: Colors.grey.shade500),
                        const SizedBox(height: 10),
                        const Text(
                          "Upload recipient's Alipay QR code",
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4B5563)),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: onPick,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          ),
                          child: const Text('Choose Image', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
