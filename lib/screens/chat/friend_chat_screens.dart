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
  });

  final int conversationId;
  final String recipientName;

  @override
  State<ChatTransferScreen> createState() => _ChatTransferScreenState();
}

class _ChatTransferScreenState extends State<ChatTransferScreen> {
  final _amount = TextEditingController();
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
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final parsed = double.tryParse(_amount.text.trim().replaceAll(',', ''));
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
    final next = '${_amount.text}$digit';
    if (next.replaceAll('.', '').length > 10) return;
    if (digit == '.' && _amount.text.contains('.')) return;
    setState(() => _amount.text = next);
  }

  void _backspace() {
    if (_amount.text.isEmpty) return;
    setState(() => _amount.text = _amount.text.substring(0, _amount.text.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<AppStore>().wallet;
    final available = wallet?.availableBalance ?? 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Transfer to ${widget.recipientName}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                children: [
                  Text(
                    'Wallet balance ${_money.format(available)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Transfer amount',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'GH₵',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _amount,
                          readOnly: true,
                          showCursor: true,
                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '0.00',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (!showNote)
                    TextButton(
                      onPressed: () => setState(() => showNote = true),
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Add Note', style: TextStyle(color: Color(0xFF2563EB))),
                      ),
                    )
                  else
                    TextField(
                      controller: _note,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        hintText: 'What is this for?',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      childAspectRatio: 1.55,
                      children: [
                        for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'])
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (d == '⌫') {
                                _backspace();
                              } else {
                                _appendDigit(d);
                              }
                            },
                            child: Center(
                              child: Text(
                                d,
                                style: TextStyle(
                                  fontSize: d == '⌫' ? 22 : 26,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const RotatedBox(
                              quarterTurns: 0,
                              child: Text(
                                'Transfer',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
    );
  }
}
