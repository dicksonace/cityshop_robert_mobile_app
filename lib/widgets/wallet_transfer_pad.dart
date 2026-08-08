import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_config.dart';
import '../store/app_store.dart';

final _money = NumberFormat.currency(locale: 'en_GH', symbol: 'GH₵', decimalDigits: 2);

/// WeChat-style transfer pad used by chat transfer and QR scan-to-pay.
class WalletTransferPad extends StatefulWidget {
  const WalletTransferPad({
    super.key,
    required this.recipientName,
    required this.onSubmit,
    this.recipientMobile,
    this.recipientAvatar,
    this.lockedAmount,
    this.actionLabel = 'Transfer',
    this.onBack,
  });

  final String recipientName;
  final String? recipientMobile;
  final String? recipientAvatar;
  /// When set (e.g. fixed-amount QR), keypad edits are disabled.
  final double? lockedAmount;
  final String actionLabel;
  final VoidCallback? onBack;
  final Future<void> Function(double amount, String? note) onSubmit;

  @override
  State<WalletTransferPad> createState() => _WalletTransferPadState();
}

class _WalletTransferPadState extends State<WalletTransferPad> {
  late String _amount;
  final _note = TextEditingController();
  bool showNote = false;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    final locked = widget.lockedAmount;
    _amount = locked != null && locked > 0 ? locked.toStringAsFixed(2) : '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadWallet();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _locked => widget.lockedAmount != null && widget.lockedAmount! > 0;

  double? get _parsedAmount {
    if (_amount.isEmpty) return null;
    return double.tryParse(_amount);
  }

  Future<void> _send() async {
    final parsed = _parsedAmount;
    if (parsed == null || parsed < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least GH₵1.00')),
      );
      return;
    }

    setState(() => sending = true);
    try {
      await widget.onSubmit(
        parsed,
        showNote && _note.text.trim().isNotEmpty ? _note.text.trim() : null,
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _appendDigit(String digit) {
    if (_locked) return;
    if (digit == '.' && _amount.contains('.')) return;
    if (_amount == '0' && digit != '.') {
      setState(() => _amount = digit);
      return;
    }
    final next = '$_amount$digit';
    final parts = next.split('.');
    if (parts[0].length > 8) return;
    if (parts.length > 1 && parts[1].length > 2) return;
    setState(() => _amount = next);
  }

  void _backspace() {
    if (_locked) return;
    if (_amount.isEmpty) return;
    setState(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  Widget _keyCell({
    required VoidCallback? onTap,
    Widget? child,
    String? label,
    Color? background,
  }) {
    return Material(
      color: background ?? Colors.white,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: Center(
          child: child ??
              Text(
                label ?? '',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111111),
                ),
              ),
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    final letter = widget.recipientName.trim().isNotEmpty
        ? widget.recipientName.trim()[0].toUpperCase()
        : '?';
    return ColoredBox(
      color: const Color(0xFF07C160),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<AppStore>().wallet;
    final available = wallet?.availableBalance ?? 0;
    final canSend = (_parsedAmount ?? 0) >= 1 && !sending;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final avatar = widget.recipientAvatar;
    final mobile = (widget.recipientMobile ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF111111)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Transfer to ${widget.recipientName}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111111),
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Balance: ${_money.format(available)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF888888),
                                  height: 1.2,
                                ),
                              ),
                              if (mobile.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  mobile,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFB2B2B2),
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: avatar != null && avatar.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: ApiConfig.resolveMediaUrl(avatar),
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => _avatarFallback(),
                                  )
                                : _avatarFallback(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    const Text(
                      'Transfer amount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF888888),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'GH₵',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111111),
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _amount,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111111),
                            height: 1,
                          ),
                        ),
                        if (!_locked)
                          Container(
                            width: 2,
                            height: 34,
                            margin: const EdgeInsets.only(left: 3),
                            color: const Color(0xFF07C160),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(height: 0.5, color: const Color(0xFFE5E5E5)),
                    const SizedBox(height: 10),
                    if (!showNote)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () => setState(() => showNote = true),
                          child: const Text(
                            'Add Note',
                            style: TextStyle(
                              color: Color(0xFF576B95),
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      )
                    else
                      TextField(
                        controller: _note,
                        autofocus: true,
                        maxLength: 120,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'Add a note',
                          hintStyle: TextStyle(color: Color(0xFFB2B2B2)),
                          border: InputBorder.none,
                          isDense: true,
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            Container(
              color: const Color(0xFFD2D3D8),
              padding: EdgeInsets.only(bottom: bottomPad),
              child: SizedBox(
                height: 256,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          for (final row in const [
                            ['1', '2', '3'],
                            ['4', '5', '6'],
                            ['7', '8', '9'],
                            ['', '0', '.'],
                          ])
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final key in row)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(0.4),
                                        child: key.isEmpty
                                            ? const ColoredBox(color: Color(0xFFD2D3D8))
                                            : _keyCell(
                                                label: key,
                                                onTap: _locked ? null : () => _appendDigit(key),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(0.4),
                              child: _keyCell(
                                onTap: _locked ? null : _backspace,
                                background: const Color(0xFFE8E9ED),
                                child: const Icon(Icons.backspace_outlined, size: 22, color: Color(0xFF111111)),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(0.4),
                              child: Material(
                                color: canSend
                                    ? const Color(0xFF07C160)
                                    : const Color(0xFF07C160).withValues(alpha: 0.35),
                                child: InkWell(
                                  onTap: canSend ? _send : null,
                                  child: Center(
                                    child: sending
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            widget.actionLabel,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
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
          ],
        ),
      ),
    );
  }
}
