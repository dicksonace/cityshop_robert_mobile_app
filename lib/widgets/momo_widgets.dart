import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Ghana mobile money networks, mirroring the web `MOMO_NETWORKS` list so the
/// app and the site describe and colour the same networks identically.
class MomoNetwork {
  const MomoNetwork({
    required this.id,
    required this.label,
    required this.numberLabel,
    required this.mark,
    required this.markColors,
    required this.markTextColor,
    required this.accent,
    required this.selectedBorder,
    required this.selectedFill,
  });

  final String id;
  final String label;

  /// Field label shown above the account / till number.
  final String numberLabel;

  /// Short brand mark drawn on the logo tile.
  final String mark;
  final List<Color> markColors;
  final Color markTextColor;
  final Color accent;
  final Color selectedBorder;
  final Color selectedFill;
}

const momoNetworks = <MomoNetwork>[
  MomoNetwork(
    id: 'mtn',
    label: 'MTN Mobile Money',
    numberLabel: 'MoMo number',
    mark: 'MTN',
    markColors: [Color(0xFFFACC15), Color(0xFFF59E0B)],
    markTextColor: Color(0xFF111827),
    accent: Color(0xFFA16207),
    selectedBorder: Color(0xFFEAB308),
    selectedFill: Color(0xFFFEFCE8),
  ),
  MomoNetwork(
    id: 'telecel',
    label: 'Telecel Cash',
    numberLabel: 'Till number',
    mark: 'TC',
    markColors: [Color(0xFFDC2626), Color(0xFFBE123C)],
    markTextColor: Colors.white,
    accent: Color(0xFFB91C1C),
    selectedBorder: Color(0xFFEF4444),
    selectedFill: Color(0xFFFEF2F2),
  ),
  MomoNetwork(
    id: 'airteltigo',
    label: 'AirtelTigo Cash',
    numberLabel: 'MoMo number',
    mark: 'AT',
    markColors: [Color(0xFFEF4444), Color(0xFF0284C7)],
    markTextColor: Colors.white,
    accent: Color(0xFF1D4ED8),
    selectedBorder: Color(0xFF3B82F6),
    selectedFill: Color(0xFFEFF6FF),
  ),
];

/// Normalize free-text network names to mtn|telecel|airteltigo.
String? normalizeMomoNetworkId(String? network) {
  final raw = (network ?? '').trim();
  if (raw.isEmpty) return null;
  final compact = raw.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (compact == 'mtn' || compact == 'telecel' || compact == 'airteltigo') return compact;
  if (compact.contains('mtn')) return 'mtn';
  if (compact.contains('telecel') || compact.contains('vodafone')) return 'telecel';
  if (compact.contains('airtel') || compact.contains('tigo')) return 'airteltigo';
  return null;
}

MomoNetwork? momoNetworkMeta(String? network) {
  final id = normalizeMomoNetworkId(network);
  if (id == null) return null;
  for (final item in momoNetworks) {
    if (item.id == id) return item;
  }
  return null;
}

String momoNetworkLabel(String? network) {
  return momoNetworkMeta(network)?.label ?? (network ?? '').replaceAll('_', ' ');
}

/// Telecel and short codes are paid into a till rather than a phone number.
String momoNumberFieldLabel(String? network, String? accountNumber) {
  final id = normalizeMomoNetworkId(network);
  if (id == 'telecel') return 'Till number';
  final digits = (accountNumber ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 4 && digits.length <= 6) return 'Till number';
  return momoNetworkMeta(id)?.numberLabel ?? 'MoMo number';
}

/// Compact MTN / Telecel / AirtelTigo selector.
/// With [selectedOnly], shows one network and a Change action — not all three at once.
class MomoNetworkPicker extends StatefulWidget {
  const MomoNetworkPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabledNetworks,
    this.label = 'Network',
    this.hint = 'Tap to change network',
    this.selectedOnly = false,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final Set<String>? enabledNetworks;
  final String label;
  final String hint;
  final bool selectedOnly;

  @override
  State<MomoNetworkPicker> createState() => _MomoNetworkPickerState();
}

class _MomoNetworkPickerState extends State<MomoNetworkPicker> {
  bool _enabled(String id) => widget.enabledNetworks?.contains(id) ?? true;

  Future<void> _pickNetwork(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose network',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                for (final network in momoNetworks) ...[
                  ListTile(
                    enabled: _enabled(network.id),
                    leading: MomoNetworkLogo(network: network.id, size: 36),
                    title: Text(
                      network.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: widget.value == network.id
                        ? Icon(Icons.check_circle, color: network.selectedBorder)
                        : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: _enabled(network.id)
                        ? () => Navigator.pop(ctx, network.id)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedOnly && widget.value != null) {
      final meta = momoNetworkMeta(widget.value);
      return Material(
        color: meta?.selectedFill ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pickNetwork(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: meta?.selectedBorder ?? const Color(0xFFE5E7EB), width: 2),
            ),
            child: Row(
              children: [
                MomoNetworkLogo(network: widget.value, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    momoNetworkLabel(widget.value),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                Text(
                  'Change',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: meta?.accent ?? AppColors.primary,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: meta?.accent ?? AppColors.primary),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.selectedOnly) ...[
          Row(
            children: [
              Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const Spacer(),
              if (widget.value != null)
                Text(
                  widget.hint,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            for (final network in momoNetworks) ...[
              if (network != momoNetworks.first) const SizedBox(width: 8),
              Expanded(
                child: _CompactNetworkChip(
                  network: network,
                  selected: widget.value == network.id,
                  enabled: _enabled(network.id),
                  onTap: () => widget.onChanged(network.id),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CompactNetworkChip extends StatelessWidget {
  const _CompactNetworkChip({
    required this.network,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final MomoNetwork network;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? network.selectedFill : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? network.selectedBorder : const Color(0xFFE5E7EB),
          width: selected ? 2 : 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MomoNetworkLogo(network: network.id, size: 32),
          const SizedBox(height: 6),
          Text(
            network.id == 'mtn'
                ? 'MTN'
                : network.id == 'telecel'
                    ? 'Telecel'
                    : 'AT',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: selected ? network.accent : AppColors.textPrimary,
            ),
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(Icons.check_circle, size: 14, color: network.selectedBorder),
            ),
        ],
      ),
    );

    if (!enabled) {
      return Opacity(opacity: 0.4, child: child);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Brand-coloured network mark (not an official trademark), same as the web.
class MomoNetworkLogo extends StatelessWidget {
  const MomoNetworkLogo({super.key, this.network, this.size = 40});

  final String? network;
  final double size;

  @override
  Widget build(BuildContext context) {
    final meta = momoNetworkMeta(network);
    final colors = meta?.markColors ?? const [Color(0xFF475569), Color(0xFF1E293B)];

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        meta?.mark ?? 'MoMo',
        style: TextStyle(
          color: meta?.markTextColor ?? Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.3,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// The "pay to" card: who to pay, the number to send to, the account name, and
/// a copy button — the mobile twin of the web `DirectPaymentDetails`.
class PaymentDetailsCard extends StatefulWidget {
  const PaymentDetailsCard({
    super.key,
    required this.accountNumber,
    required this.accountName,
    this.network,
    this.isBank = false,
    this.bankName,
    this.hint,
  });

  final String accountNumber;
  final String accountName;
  final String? network;
  final bool isBank;
  final String? bankName;
  final String? hint;

  @override
  State<PaymentDetailsCard> createState() => _PaymentDetailsCardState();
}

class _PaymentDetailsCardState extends State<PaymentDetailsCard> {
  bool copied = false;
  Timer? _resetCopied;

  static const _sky = Color(0xFF0369A1);

  @override
  void dispose() {
    _resetCopied?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (widget.accountNumber.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.accountNumber));
    if (!mounted) return;
    setState(() => copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.isBank ? 'Account' : 'MoMo'} number copied')),
    );
    _resetCopied?.cancel();
    _resetCopied = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isBank
        ? ((widget.bankName ?? '').isNotEmpty ? widget.bankName! : 'Bank transfer')
        : (momoNetworkLabel(widget.network).isNotEmpty
            ? momoNetworkLabel(widget.network)
            : 'Mobile Money');
    final numberLabel =
        widget.isBank ? 'Account number' : momoNumberFieldLabel(widget.network, widget.accountNumber);
    final nameLines = widget.accountName
        .split(RegExp(r'\n|\s*/\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomPaint(
          painter: _DashedBorderPainter(color: const Color(0xFF7DD3FC), radius: 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FDFF),
                    border: Border(bottom: BorderSide(color: Color(0xFFE0F2FE))),
                  ),
                  child: Row(
                    children: [
                      if (widget.isBank)
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.account_balance, color: Colors.white, size: 20),
                        )
                      else
                        MomoNetworkLogo(network: widget.network),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PAY TO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: _sky,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xFFFCFEFF),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              numberLabel.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.accountNumber,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (nameLines.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'ACCOUNT NAME',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              for (final line in nameLines)
                                Text(
                                  line.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.3,
                                    fontWeight: FontWeight.w800,
                                    color: _sky,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: copied ? AppColors.emerald : const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _copy,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Text(
                              copied ? 'COPIED' : 'COPY',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if ((widget.hint ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.hint!,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          ),
        ],
      ],
    );
  }
}

/// Draws the dashed outline the web card uses; Flutter has no dashed border.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.7),
      );

    const dash = 5.0;
    const gap = 3.5;
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
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
