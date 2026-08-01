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
