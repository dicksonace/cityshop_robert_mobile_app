import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';

final _money = NumberFormat.currency(locale: 'en_GH', symbol: 'GH₵', decimalDigits: 2);

/// Search a registered CityShop mobile number and open a friend chat.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _mobile = TextEditingController();
  bool searching = false;
  bool opening = false;
  String? error;
  Map<String, dynamic>? found;

  @override
  void dispose() {
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final value = _mobile.text.trim();
    if (value.isEmpty) {
      setState(() => error = 'Enter a mobile number registered on CityShop');
      return;
    }
    setState(() {
      searching = true;
      error = null;
      found = null;
    });
    try {
      final user = await context.read<AppStore>().lookupUserByMobile(value);
      if (!mounted) return;
      setState(() => found = user);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _startChat() async {
    final user = found;
    if (user == null) return;
    final id = user['id'];
    if (id is! int && id is! num) return;
    setState(() => opening = true);
    try {
      final opened = await context.read<AppStore>().openConversation(
            sellerId: (id as num).toInt(),
            userId: (id).toInt(),
          );
      if (!mounted) return;
      context.pushReplacement('/messages/${opened.conversation.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Search by mobile number',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            'Find friends already registered on CityShop and start chatting.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _mobile,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Mobile number',
              hintText: 'e.g. 0244123456',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: searching ? null : _search,
                icon: searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: searching ? 'Searching…' : 'Search CityShop',
            loading: searching,
            onPressed: searching ? null : _search,
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(error!, style: const TextStyle(color: AppColors.danger)),
          ],
          if (found != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  _LookupAvatar(
                    name: '${found!['name'] ?? 'U'}',
                    avatar: found!['avatar'] as String?,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${found!['name'] ?? 'CityShop user'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${found!['mobile'] ?? ''}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        if ((found!['role'] as String?) != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${found!['role']}'.toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: opening ? 'Opening…' : 'Chat',
              loading: opening,
              onPressed: opening ? null : _startChat,
            ),
          ],
        ],
      ),
    );
  }
}

class _LookupAvatar extends StatelessWidget {
  const _LookupAvatar({required this.name, this.avatar});

  final String name;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final url = ApiConfig.resolveMediaUrl(avatar);
    final initial = name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();
    return ClipOval(
      child: SizedBox(
        width: 52,
        height: 52,
        child: url.isEmpty
            ? ColoredBox(
                color: AppColors.ringOrange,
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
              )
            : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
      ),
    );
  }
}

/// WeChat-style transfer sheet — amount in GHS from CityShop wallet.
class ChatTransferScreen extends StatefulWidget {
  const ChatTransferScreen({
    super.key,
    required this.conversationId,
    required this.recipientName,
    this.recipientMobile,
    this.recipientAvatar,
  });

  final int conversationId;
  final String recipientName;
  final String? recipientMobile;
  final String? recipientAvatar;

  @override
  State<ChatTransferScreen> createState() => _ChatTransferScreenState();
}

class _ChatTransferScreenState extends State<ChatTransferScreen> {
  String _amount = '';
  final _note = TextEditingController();
  bool showNote = false;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadWallet();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

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

    final store = context.read<AppStore>();
    if (!(store.user?.hasPaymentPin ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a payment PIN first in Profile → Payment PIN')),
      );
      return;
    }

    final pin = await promptPaymentPin(
      context,
      title: 'Confirm transfer',
      subtitle: 'Enter your PIN to send ${_money.format(parsed)} to ${widget.recipientName}',
    );
    if (pin == null || !mounted) return;

    setState(() => sending = true);
    try {
      final msg = await store.sendTransferMessage(
        widget.conversationId,
        amount: parsed,
        note: showNote ? _note.text.trim() : null,
        paymentPin: pin,
      );
      if (!mounted) return;
      Navigator.pop(context, msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _appendDigit(String digit) {
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
    if (_amount.isEmpty) return;
    setState(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  Widget _keyCell({
    required VoidCallback? onTap,
    Widget? child,
    String? label,
    Color? background,
    Color? foreground,
  }) {
    return Material(
      color: background ?? const Color(0xFFF3F4F6),
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
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: foreground ?? AppColors.textPrimary,
                ),
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const SizedBox.shrink(),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transfer to ${widget.recipientName}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mobile.isNotEmpty
                                  ? 'Mobile: $mobile'
                                  : 'CityShop wallet · ${_money.format(available)} available',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (mobile.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Balance ${_money.format(available)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: avatar != null && avatar.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: ApiConfig.resolveMediaUrl(avatar),
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _avatarFallback(),
                                )
                              : _avatarFallback(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Transfer amount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'GH₵',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _amount,
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 36,
                        margin: const EdgeInsets.only(left: 2),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 8),
                  if (!showNote)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => showNote = true),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Add Note',
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  else
                    TextField(
                      controller: _note,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        hintText: 'Add a note',
                        border: InputBorder.none,
                        counterText: '',
                      ),
                    ),
                ],
              ),
            ),
          ),
          // WeChat-style keypad: numbers + backspace top-right + tall Transfer.
          Container(
            color: const Color(0xFFE5E7EB),
            padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 0),
            child: SizedBox(
              height: 248,
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
                                      padding: const EdgeInsets.all(0.5),
                                      child: key.isEmpty
                                          ? const ColoredBox(color: Color(0xFFF3F4F6))
                                          : _keyCell(
                                              label: key,
                                              onTap: () => _appendDigit(key),
                                              background: Colors.white,
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
                            padding: const EdgeInsets.all(0.5),
                            child: _keyCell(
                              onTap: _backspace,
                              background: const Color(0xFFF3F4F6),
                              child: const Icon(Icons.backspace_outlined, size: 22),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(0.5),
                            child: Material(
                              color: canSend
                                  ? const Color(0xFF07C160)
                                  : const Color(0xFFA7F3D0),
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
                                          'Transfer',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: canSend ? Colors.white : Colors.white70,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
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
    );
  }

  Widget _avatarFallback() {
    final letter = widget.recipientName.trim().isNotEmpty
        ? widget.recipientName.trim()[0].toUpperCase()
        : '?';
    return ColoredBox(
      color: AppColors.ringOrange,
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
