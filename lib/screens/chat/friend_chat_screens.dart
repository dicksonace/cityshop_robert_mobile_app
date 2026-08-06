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
                onPressed: () => Navigator.pop(context),
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
                                mobile.isNotEmpty
                                    ? 'Mobile: $mobile'
                                    : 'Balance: ${_money.format(available)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF888888),
                                  height: 1.2,
                                ),
                              ),
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
                                    errorWidget: (_, __, ___) => _avatarFallback(),
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
                    if (mobile.isNotEmpty)
                      Text(
                        'Available ${_money.format(available)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB2B2B2)),
                      ),
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
                                                onTap: () => _appendDigit(key),
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
                                onTap: _backspace,
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
                                        : const Text(
                                            'Transfer',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
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
}
