import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';
import '../../widgets/payment_success_screen.dart';
import '../../widgets/wallet_transfer_pad.dart';

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
class ChatTransferScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return WalletTransferPad(
      recipientName: recipientName,
      recipientMobile: recipientMobile,
      recipientAvatar: recipientAvatar,
      onBack: () => Navigator.pop(context),
      onSubmit: (amount, note) async {
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
          subtitle: 'Enter your PIN to send ${_money.format(amount)} to $recipientName',
        );
        if (pin == null || !context.mounted) return;

        try {
          final msg = await store.sendTransferMessage(
            conversationId,
            amount: amount,
            note: note,
            paymentPin: pin,
          );
          if (!context.mounted) return;
          final ref = (msg.transferReference ?? '').trim();
          await showPaymentSuccess(
            context,
            amount: amount,
            recipientName: recipientName,
            reference: ref.isEmpty ? null : ref,
            note: note,
          );
          if (!context.mounted) return;
          Navigator.pop(context, msg);
        } on ApiException catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      },
    );
  }
}
