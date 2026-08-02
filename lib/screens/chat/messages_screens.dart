import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/image_viewer.dart';

final _timeFmt = DateFormat('h:mm a');
final _dayFmt = DateFormat('EEE, MMM d');
final _money = NumberFormat.currency(locale: 'en_GH', symbol: 'GH₵', decimalDigits: 2);

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      setState(() => loading = false);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await store.loadConversations();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.accent),
              const SizedBox(height: 12),
              const Text('Login to chat with sellers', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Ask about stock, delivery, or negotiate before you buy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => context.push('/login'), child: const Text('Login')),
            ],
          ),
        ),
      );
    }
    if (loading) return const FullPageLoader(label: 'Loading messages…');
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error!, textAlign: TextAlign.center),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (store.conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.ringOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.forum_outlined, size: 36, color: AppColors.accent),
              ),
              const SizedBox(height: 16),
              const Text('No conversations yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 8),
              const Text(
                'Open a product and tap Chat to message the seller.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: store.conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final c = store.conversations[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: _ConversationAvatar(name: c.otherName, avatar: c.otherAvatar, radius: 24),
            title: Text(c.otherName, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.productName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    c.productName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  c.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            isThreeLine: c.productName != null,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (c.lastMessageAt != null)
                  Text(
                    _shortTime(c.lastMessageAt!),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                if (c.unreadCount > 0) ...[
                  const SizedBox(height: 6),
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: AppColors.accent,
                    child: Text('${c.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ],
              ],
            ),
            onTap: () => context.push('/messages/${c.id}'),
          );
        },
      ),
    );
  }

  String _shortTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return _timeFmt.format(dt);
    }
    return DateFormat('MMM d').format(dt);
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final int conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  ConversationModel? conversation;
  List<ChatMessage> messages = [];
  bool loading = true;
  bool sending = false;
  bool uploadingImage = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _pollNew());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppStore>().loadConversation(widget.conversationId);
      if (!mounted) return;
      setState(() {
        conversation = result.conversation;
        messages = result.messages;
        loading = false;
      });
      _jumpToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _pollNew() async {
    if (messages.isEmpty || !mounted) return;
    try {
      final newer = await context.read<AppStore>().pollMessages(
            widget.conversationId,
            messages.last.id,
          );
      if (newer.isEmpty || !mounted) return;
      setState(() => messages = [...messages, ...newer]);
      _jumpToEnd();
    } catch (_) {}
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    if (!message.canDelete && !(message.mine && !message.isDeleted && message.type == 'text')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This message can no longer be deleted')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This removes the wrong message for both of you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await context.read<AppStore>().deleteMessage(widget.conversationId, message.id);
      if (!mounted) return;
      setState(() {
        messages = [
          for (final m in messages)
            if (m.id == updated.id) updated else m,
        ];
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || sending || uploadingImage) return;
    setState(() => sending = true);
    try {
      final msg = await context.read<AppStore>().sendMessage(widget.conversationId, text);
      if (preset == null) _controller.clear();
      setState(() => messages = [...messages, msg]);
      _jumpToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (sending || uploadingImage) return;

    final source = await showAppSheet<ImageSource>(
      context: context,
      builder: (ctx) => SheetShell(
        children: [
          const Text('Send a photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          const Text(
            'Take a picture or choose one from your gallery.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.ringOrange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
            ),
            title: const Text('Take photo', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.ringOrange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
            ),
            title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    );

    if (source == null || !mounted) return;

    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;

    final caption = _controller.text.trim();
    setState(() => uploadingImage = true);
    try {
      final msg = await context.read<AppStore>().sendImageMessage(
            widget.conversationId,
            file.path,
            caption: caption.isEmpty ? null : caption,
            filename: file.name.isNotEmpty ? file.name : 'chat.jpg',
          );
      if (!mounted) return;
      if (caption.isNotEmpty) _controller.clear();
      setState(() => messages = [...messages, msg]);
      _jumpToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send that photo. Try another one.')),
        );
      }
    } finally {
      if (mounted) setState(() => uploadingImage = false);
    }
  }

  Future<void> _callSeller() async {
    final mobile = conversation?.otherMobile?.trim();
    if (mobile == null || mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone number is not available')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: mobile.replaceAll(RegExp(r'[^\d+]'), ''));
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dial $mobile')),
        );
      }
    }
  }

  /// Call setup rows come down the same endpoint; they are not chat messages.
  List<ChatMessage> get thread => messages.where((m) => !m.isSignalling).toList();

  String? _time(String? iso) => iso == null ? null : _timeLabel(iso);

  @override
  Widget build(BuildContext context) {
    final title = conversation?.otherName ?? 'Chat';
    final thread = this.thread;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _ConversationAvatar(
              name: title,
              avatar: conversation?.otherAvatar,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        actions: [
          if ((conversation?.otherMobile ?? '').trim().isNotEmpty)
            IconButton(
              tooltip: 'Call seller',
              onPressed: _callSeller,
              icon: const Icon(Icons.call_rounded, color: AppColors.accent),
            ),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Opening chat…')
          : Column(
              children: [
                if (conversation?.productName != null)
                  _ProductContextCard(conversation: conversation!),
                Expanded(
                  child: thread.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Say hello to the seller', style: TextStyle(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                const Text(
                                  'Ask about availability, delivery time, or payment.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    for (final q in const [
                                      'Is this still available?',
                                      'How long is delivery?',
                                      'Can you deliver today?',
                                    ])
                                      ActionChip(
                                        label: Text(q),
                                        onPressed: sending ? null : () => _send(q),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                          itemCount: thread.length,
                          itemBuilder: (context, index) {
                            final m = thread[index];
                            final showDay = index == 0 ||
                                _dayKey(thread[index - 1].createdAt) != _dayKey(m.createdAt);
                            return Column(
                              children: [
                                if (showDay && m.createdAt != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black12,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _dayLabel(m.createdAt!),
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                if (m.isEvent)
                                  _EventChip(label: m.eventLabel, time: _time(m.createdAt))
                                else
                                Align(
                                  alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                                    ),
                                    child: GestureDetector(
                                      onLongPress: m.isDeleted
                                          ? null
                                          : (m.canDelete || (m.mine && m.type == 'text'))
                                              ? () => _deleteMessage(m)
                                              : null,
                                      child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: m.isPhoto
                                          ? const EdgeInsets.all(4)
                                          : const EdgeInsets.fromLTRB(12, 10, 12, 8),
                                      decoration: BoxDecoration(
                                        color: m.isDeleted
                                            ? Colors.grey.shade200
                                            : (m.mine ? AppColors.accent : Colors.white),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(m.mine ? 16 : 4),
                                          bottomRight: Radius.circular(m.mine ? 4 : 16),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          if (m.isPhoto) ...[
                                            _ChatPhoto(
                                              url: m.imageUrl!,
                                              caption: m.body.trim(),
                                            ),
                                            if (m.body.trim().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                                                child: Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: Text(
                                                    m.body.trim(),
                                                    style: TextStyle(
                                                      color: m.mine ? Colors.white : AppColors.textPrimary,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ] else
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                m.isDeleted ? 'Message deleted' : m.body,
                                                style: TextStyle(
                                                  color: m.isDeleted
                                                      ? AppColors.textMuted
                                                      : (m.mine ? Colors.white : AppColors.textPrimary),
                                                  fontStyle: m.isDeleted ? FontStyle.italic : FontStyle.normal,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ),
                                          if (m.createdAt != null) ...[
                                            const SizedBox(height: 4),
                                            Padding(
                                              padding: EdgeInsets.only(right: m.isPhoto ? 6 : 0),
                                              child: Text(
                                                _timeLabel(m.createdAt!),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: m.isDeleted
                                                      ? AppColors.textMuted
                                                      : (m.mine ? Colors.white70 : AppColors.textMuted),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Send photo',
                          onPressed: (sending || uploadingImage) ? null : _pickAndSendImage,
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            disabledForegroundColor: AppColors.textMuted,
                          ),
                          icon: uploadingImage
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                )
                              : const Icon(Icons.image_outlined),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            minLines: 1,
                            maxLines: 4,
                            enabled: !uploadingImage,
                            textInputAction: TextInputAction.send,
                            decoration: InputDecoration(
                              hintText: uploadingImage ? 'Sending photo…' : 'Type a message…',
                              filled: true,
                              fillColor: AppColors.background,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: (sending || uploadingImage) ? null : _send,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            disabledBackgroundColor: AppColors.ringOrange,
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String? _dayKey(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return null;
    return '${dt.year}-${dt.month}-${dt.day}';
  }

  String _dayLabel(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday';
    }
    return _dayFmt.format(dt);
  }

  String _timeLabel(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return _timeFmt.format(dt);
  }
}

/// The product the chat is about: tap to open it on the storefront.
class _ProductContextCard extends StatelessWidget {
  const _ProductContextCard({required this.conversation});

  final ConversationModel conversation;

  @override
  Widget build(BuildContext context) {
    final slug = conversation.productSlug ?? '';
    final photo = ApiConfig.resolveMediaUrl(conversation.productImage);
    final price = conversation.productPrice;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: slug.isEmpty ? null : () => context.push('/products/$slug'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 40,
                  height: 40,
                  color: AppColors.background,
                  child: photo.isEmpty
                      ? const Icon(Icons.shopping_bag_outlined, size: 18, color: AppColors.accent)
                      : CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.productName ?? 'Product',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price == null ? 'Chatting about this item' : _money.format(price),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: price == null ? FontWeight.w500 : FontWeight.w800,
                        color: price == null ? AppColors.textSecondary : AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              if (slug.isNotEmpty)
                const Row(
                  children: [
                    Text(
                      'View',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primary),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calls and other non-chat events sit in the middle of the thread.
class _EventChip extends StatelessWidget {
  const _EventChip({required this.label, this.time});

  final String label;
  final String? time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.call_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                time == null ? label : '$label · $time',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatPhoto extends StatelessWidget {
  const _ChatPhoto({required this.url, required this.caption});

  final String url;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.resolveMediaUrl(url);

    return GestureDetector(
      onTap: () => showImageViewer(context, urls: [resolved]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, minWidth: 180),
          child: CachedNetworkImage(
            imageUrl: resolved,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 180,
              height: 180,
              color: AppColors.background,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 180,
              height: 120,
              color: AppColors.background,
              child: const Center(
                child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({
    required this.name,
    required this.avatar,
    required this.radius,
  });

  final String name;
  final String? avatar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = ApiConfig.resolveMediaUrl(avatar);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.ringOrange,
      backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
      child: url.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.75,
              ),
            )
          : null,
    );
  }
}
