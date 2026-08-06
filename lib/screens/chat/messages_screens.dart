import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/chat_realtime.dart';
import '../../models/models.dart';
import '../../services/chat_call_service.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_call_overlay.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/tab_refresh.dart';
import '../../widgets/video_viewer.dart';
import 'friend_chat_screens.dart';

final _timeFmt = DateFormat('h:mm a');
final _dayFmt = DateFormat('EEE, MMM d');
final _money = NumberFormat.currency(locale: 'en_GH', symbol: 'GH₵', decimalDigits: 2);

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> with AutoRefreshTab {
  bool loading = true;
  String? error;

  @override
  int? get tabIndex => 3;

  @override
  Future<void> refreshTabData({required bool background}) => _load(background: background);

  Future<void> _load({bool background = false}) async {
    final store = context.read<AppStore>();
    if (!store.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (!background) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await store.loadConversations();
      await store.refreshNotificationCounts();
      error = null;
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
      if (tabIsWarmingUp) return const FullPageLoader(label: 'Loading messages…');

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.accent),
              const SizedBox(height: 12),
              const Text('Login to open your chat room', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Message sellers, chat with friends, and send GH₵ transfers.',
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
            TextButton(onPressed: refreshNow, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (store.conversations.isEmpty) {
      // Scrollable so an empty inbox can still be pulled down to refresh.
      return RefreshIndicator(
        onRefresh: refreshNow,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.ringOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.forum_outlined, size: 36, color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No conversations yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search a CityShop mobile number to chat with friends, or open a product and tap Chat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => context.push('/messages/new'),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Find friend by mobile'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Chats',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                ),
              ),
              IconButton(
                tooltip: 'Search mobile number',
                onPressed: () => context.push('/messages/new'),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'New chat',
                onPressed: () => context.push('/messages/new'),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
      onRefresh: refreshNow,
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
          ),
        ),
      ],
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
  const ChatScreen({super.key, required this.conversationId, this.attachProduct});
  final int conversationId;
  final AttachProduct? attachProduct;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  ConversationModel? conversation;
  List<ChatMessage> messages = [];
  AttachProduct? pendingProduct;
  bool loading = true;
  bool sending = false;
  bool sendingProduct = false;
  bool uploadingMedia = false;
  bool showAttachPanel = false;
  bool recordingVoice = false;
  int recordSeconds = 0;
  ChatMessage? replyingTo;
  Timer? _poll;
  Timer? _recordTick;
  final _recorder = AudioRecorder();
  ConversationRealtime? _realtime;
  bool _realtimeLive = false;
  ChatCallService? _call;

  @override
  void initState() {
    super.initState();
    pendingProduct = widget.attachProduct;
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _recordTick?.cancel();
    unawaited(_realtime?.dispose() ?? Future<void>.value());
    unawaited(_call?.disposeService() ?? Future<void>.value());
    _recorder.dispose();
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final store = context.read<AppStore>();
      final result = await store.loadConversation(widget.conversationId);
      if (!mounted) return;
      final myId = store.user?.id ?? 0;
      _call ??= ChatCallService(
        store: store,
        conversationId: widget.conversationId,
        myUserId: myId,
        myName: store.user?.name ?? 'You',
        onCallLog: (msg) {
          if (!mounted) return;
          if (messages.any((m) => m.id == msg.id)) return;
          setState(() => messages = [...messages, msg]);
          _jumpToEnd();
        },
      );
      _call!.peerName = result.conversation.otherName;
      setState(() {
        conversation = result.conversation;
        messages = result.messages;
        loading = false;
      });
      _jumpToEnd();
      await _startRealtime(store);
      _startPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _startRealtime(AppStore store) async {
    final config = await store.fetchRealtimeConfig();
    final token = await store.apiToken;
    final myId = store.user?.id;
    if (!mounted || config == null || !config.isUsable || token == null || myId == null) {
      return;
    }

    final realtime = ConversationRealtime(
      config: config,
      token: token,
      conversationId: widget.conversationId,
      myUserId: myId,
      onMessage: (msg) {
        if (!mounted) return;
        if (messages.any((m) => m.id == msg.id)) return;
        if (msg.isSignalling) {
          unawaited(_call?.handleMessage(msg) ?? Future<void>.value());
        }
        setState(() => messages = [...messages, msg]);
        if (!msg.isSignalling) _jumpToEnd();
      },
    );

    final ok = await realtime.start();
    if (!mounted) {
      await realtime.dispose();
      return;
    }
    if (ok) {
      _realtime = realtime;
      _realtimeLive = true;
      _startPoll();
    } else {
      await realtime.dispose();
    }
  }

  void _startPoll() {
    _poll?.cancel();
    final seconds = _realtimeLive ? 15 : 4;
    _poll = Timer.periodic(Duration(seconds: seconds), (_) => _pollNew());
  }

  Future<void> _pollNew() async {
    if (!mounted) return;
    try {
      final afterId = messages.fold<int>(
        0,
        (max, m) => m.id > max ? m.id : max,
      );
      final polled = await context.read<AppStore>().pollMessages(
            widget.conversationId,
            afterId,
          );
      if (!mounted) return;
      final readSet = polled.readMessageIds.toSet();
      final existing = messages.map((m) => m.id).toSet();
      final fresh = <ChatMessage>[];
      for (final msg in polled.messages) {
        if (existing.contains(msg.id)) continue;
        fresh.add(msg);
        if (msg.isSignalling) {
          unawaited(_call?.handleMessage(msg) ?? Future<void>.value());
        }
      }
      var changed = fresh.isNotEmpty;
      final merged = [
        ...messages.map((m) {
          if (!m.mine || m.isRead || !readSet.contains(m.id)) return m;
          changed = true;
          return m.copyWith(readAt: DateTime.now().toIso8601String());
        }),
        ...fresh,
      ];
      if (!changed) return;
      setState(() => messages = merged);
      if (fresh.any((m) => !m.isSignalling)) _jumpToEnd();
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
    const deletable = {'text', 'image', 'video', 'voice', 'product'};
    if (!message.canDelete && !(message.mine && !message.isDeleted && deletable.contains(message.type))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This message can no longer be deleted')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(
          message.isMedia || message.isProduct
              ? 'This removes the shared item for both of you.'
              : 'This removes the message for both of you.',
        ),
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
    if (text.isEmpty || sending || uploadingMedia) return;
    if (conversation?.blocked == true) return;
    final replyId = replyingTo?.id;
    setState(() {
      sending = true;
      showAttachPanel = false;
    });
    try {
      final msg = await context.read<AppStore>().sendMessage(
            widget.conversationId,
            text,
            replyToId: replyId,
          );
      if (preset == null) _controller.clear();
      setState(() {
        messages = [...messages, msg];
        replyingTo = null;
      });
      _jumpToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _startReply(ChatMessage message) {
    if (message.isDeleted || message.isEvent || message.isSignalling) return;
    setState(() {
      replyingTo = message;
      showAttachPanel = false;
    });
    _focus.requestFocus();
  }

  Future<void> _openMessageActions(ChatMessage message) async {
    if (message.isDeleted) return;
    const deletable = {'text', 'image', 'video', 'voice', 'product'};
    final canReply = !message.isEvent && conversation?.blocked != true;
    final canDelete = message.canDelete ||
        (message.mine && !message.isDeleted && deletable.contains(message.type));
    if (!canReply && !canDelete) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canReply)
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: AppColors.accent),
                  title: const Text('Reply', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: message.isProduct
                      ? Text(message.productName ?? 'Product')
                      : null,
                  onTap: () => Navigator.pop(ctx, 'reply'),
                ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                  title: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'reply') {
      _startReply(message);
    } else if (action == 'delete') {
      await _deleteMessage(message);
    }
  }

  Future<void> _sendPendingProduct() async {
    final product = pendingProduct;
    if (product == null || sendingProduct || sending || uploadingMedia) return;
    setState(() => sendingProduct = true);
    try {
      final msg = await context.read<AppStore>().sendProductMessage(
            widget.conversationId,
            product.id,
          );
      if (!mounted) return;
      setState(() {
        messages = [...messages, msg];
        pendingProduct = null;
        conversation = ConversationModel(
          id: conversation?.id ?? widget.conversationId,
          otherName: conversation?.otherName ?? 'Seller',
          otherId: conversation?.otherId,
          otherAvatar: conversation?.otherAvatar,
          storeName: conversation?.storeName,
          otherMobile: conversation?.otherMobile,
          productId: product.id,
          productName: product.name,
          productSlug: product.slug,
          productImage: product.imageUrl,
          productPrice: product.price,
          latestBody: conversation?.latestBody,
          latestType: 'product',
          unreadCount: conversation?.unreadCount ?? 0,
          lastMessageAt: conversation?.lastMessageAt,
        );
      });
      _jumpToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => sendingProduct = false);
    }
  }

  void _toggleAttachPanel() {
    _focus.unfocus();
    setState(() => showAttachPanel = !showAttachPanel);
  }

  Future<void> _appendMedia(Future<ChatMessage> Function() send) async {
    if (sending || uploadingMedia) return;
    setState(() {
      uploadingMedia = true;
      showAttachPanel = false;
    });
    try {
      final msg = await send();
      if (!mounted) return;
      setState(() => messages = [...messages, msg]);
      _jumpToEnd();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        final detail = e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '').trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detail.isEmpty || detail.length > 120
                  ? 'Could not send that. Try again.'
                  : detail,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => uploadingMedia = false);
    }
  }

  Future<void> _sendPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    final caption = _controller.text.trim();
    await _appendMedia(() async {
      final msg = await context.read<AppStore>().sendImageMessage(
            widget.conversationId,
            file.path,
            caption: caption.isEmpty ? null : caption,
            filename: file.name.isNotEmpty ? file.name : 'chat.jpg',
          );
      if (caption.isNotEmpty && mounted) _controller.clear();
      return msg;
    });
  }

  Future<void> _sendVideo() async {
    final file = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (file == null || !mounted) return;
    final caption = _controller.text.trim();
    await _appendMedia(() async {
      final msg = await context.read<AppStore>().sendVideoMessage(
            widget.conversationId,
            file.path,
            caption: caption.isEmpty ? null : caption,
            filename: file.name.isNotEmpty ? file.name : 'chat.mp4',
          );
      if (caption.isNotEmpty && mounted) _controller.clear();
      return msg;
    });
  }

  Future<void> _startVoice() async {
    if (recordingVoice || uploadingMedia) return;
    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow microphone access to send voice messages')),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        recordingVoice = true;
        recordSeconds = 0;
        showAttachPanel = false;
      });
      _recordTick?.cancel();
      _recordTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => recordSeconds += 1);
        if (recordSeconds >= 120) _stopVoice(send: true);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording. ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<void> _stopVoice({required bool send}) async {
    if (!recordingVoice) return;
    _recordTick?.cancel();
    final seconds = recordSeconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    if (mounted) {
      setState(() {
        recordingVoice = false;
        recordSeconds = 0;
      });
    } else {
      recordingVoice = false;
      recordSeconds = 0;
    }

    if (path != null && path.startsWith('file://')) {
      path = Uri.parse(path).toFilePath();
    }

    if (!send || path == null || path.isEmpty) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      return;
    }
    if (seconds < 1) {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hold a little longer to record')),
        );
      }
      return;
    }

    // MediaRecorder can finish writing a beat after stop() returns.
    var uploadPath = path;
    var ready = false;
    for (var i = 0; i < 8; i++) {
      final file = File(uploadPath);
      if (await file.exists() && await file.length() > 64) {
        ready = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (!ready) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording did not save. Try again.')),
        );
      }
      return;
    }

    await _appendMedia(
      () => context.read<AppStore>().sendVoiceMessage(
            widget.conversationId,
            uploadPath,
            filename: 'voice.m4a',
            durationSeconds: seconds,
          ),
    );
  }

  Future<void> _startInAppCall(ChatCallKind kind) async {
    final call = _call;
    if (call == null) return;
    if (conversation?.blocked == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unblock this user to call')),
      );
      return;
    }
    setState(() => showAttachPanel = false);
    call.peerName = conversation?.otherName ?? 'Chat';
    try {
      await call.startCall(kind);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is StateError ? e.message : 'Could not start call')),
      );
    }
  }

  Future<void> _acceptInAppCall() async {
    try {
      await _call?.acceptCall();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is StateError ? e.message : 'Could not join call')),
      );
    }
  }

  Future<void> _endInAppCall() async {
    final call = _call;
    if (call == null) return;
    final reason = call.state == ChatCallState.active
        ? ChatCallEndReason.completed
        : call.state == ChatCallState.calling
            ? ChatCallEndReason.missed
            : call.state == ChatCallState.incoming
                ? ChatCallEndReason.declined
                : ChatCallEndReason.cancelled;
    await call.endCall(reason);
    if (mounted) setState(() {});
  }

  Future<void> _callSellerPhone() async {
    final mobile = conversation?.otherMobile?.trim();
    if (mobile == null || mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number is not available')),
      );
      return;
    }
    setState(() => showAttachPanel = false);
    final uri = Uri(scheme: 'tel', path: mobile.replaceAll(RegExp(r'[^\d+]'), ''));
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dial $mobile')),
        );
      }
    }
  }

  Future<void> _openTransfer() async {
    if (conversation?.blocked == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unblock this user to send money')),
      );
      return;
    }
    setState(() => showAttachPanel = false);
    final msg = await Navigator.of(context).push<ChatMessage>(
      MaterialPageRoute(
        builder: (_) => ChatTransferScreen(
          conversationId: widget.conversationId,
          recipientName: conversation?.otherName ?? 'friend',
          recipientMobile: conversation?.otherMobile,
          recipientAvatar: conversation?.otherAvatar,
        ),
      ),
    );
    if (!mounted || msg == null) return;
    setState(() => messages = [...messages, msg]);
    _jumpToEnd();
  }

  Future<void> _toggleBlock() async {
    final otherId = conversation?.otherId;
    if (otherId == null) return;
    final currentlyBlocked = conversation?.iBlocked == true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(currentlyBlocked ? 'Unblock user?' : 'Block user?'),
        content: Text(
          currentlyBlocked
              ? 'You will be able to chat with ${conversation?.otherName ?? 'this user'} again.'
              : 'They will not be able to message or transfer money to you.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(currentlyBlocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      if (currentlyBlocked) {
        await context.read<AppStore>().unblockUser(otherId);
      } else {
        await context.read<AppStore>().blockUser(otherId);
      }
      if (!mounted) return;
      setState(() {
        conversation = conversation?.copyWith(
          iBlocked: !currentlyBlocked,
          blocked: !currentlyBlocked,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(currentlyBlocked ? 'User unblocked' : 'User blocked')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
          IconButton(
            tooltip: 'Audio call',
            onPressed: () => unawaited(_startInAppCall(ChatCallKind.voice)),
            icon: const Icon(Icons.call_rounded, color: AppColors.accent),
          ),
          IconButton(
            tooltip: 'Video call',
            onPressed: () => unawaited(_startInAppCall(ChatCallKind.video)),
            icon: const Icon(Icons.videocam_rounded, color: Color(0xFF0284C7)),
          ),
          if (conversation?.otherId != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'block') {
                  _toggleBlock();
                } else if (value == 'phone') {
                  unawaited(_callSellerPhone());
                }
              },
              itemBuilder: (context) => [
                if ((conversation?.otherMobile ?? '').trim().isNotEmpty)
                  const PopupMenuItem(
                    value: 'phone',
                    child: Text('Call phone'),
                  ),
                PopupMenuItem(
                  value: 'block',
                  child: Text(
                    conversation?.iBlocked == true ? 'Unblock' : 'Block',
                  ),
                ),
              ],
            ),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Opening chat…')
          : Stack(
              children: [
                Column(
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
                                      onLongPress: m.isDeleted ? null : () => _openMessageActions(m),
                                      child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: m.isProduct || m.isTransfer
                                          ? EdgeInsets.zero
                                          : m.isMedia
                                              ? const EdgeInsets.all(4)
                                              : const EdgeInsets.fromLTRB(12, 10, 12, 8),
                                      decoration: BoxDecoration(
                                        color: m.isDeleted
                                            ? Colors.grey.shade200
                                            : m.isProduct || m.isTransfer
                                                ? Colors.white
                                                : (m.mine ? AppColors.accent : Colors.white),
                                        border: m.isProduct || m.isTransfer
                                            ? Border.all(
                                                color: m.isTransfer
                                                    ? const Color(0xFFBBF7D0)
                                                    : const Color(0xFFFFE0C2),
                                              )
                                            : null,
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
                                          if (m.replyTo != null && !m.isDeleted)
                                            _ReplyQuote(
                                              reply: m.replyTo!,
                                              mine: m.mine,
                                              onOpenProduct: (slug) {
                                                if (slug.isNotEmpty) context.push('/products/$slug');
                                              },
                                            ),
                                          if (m.isProduct)
                                            _ChatProductCard(message: m)
                                          else if (m.isTransfer)
                                            _ChatTransferCard(message: m)
                                          else if (m.isPhoto) ...[
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
                                          ] else if (m.isVideo) ...[
                                            _ChatVideo(url: m.videoUrl!, mine: m.mine),
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
                                          ] else if (m.isVoice)
                                            _ChatVoice(
                                              url: m.voiceUrl!,
                                              durationLabel: m.durationLabel,
                                              mine: m.mine,
                                            )
                                          else
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
                                              padding: EdgeInsets.only(
                                                right: m.isMedia || m.isProduct || m.isTransfer ? 8 : 0,
                                                bottom: m.isProduct || m.isTransfer ? 8 : 0,
                                                left: m.isProduct || m.isTransfer ? 8 : 0,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _timeLabel(m.createdAt!),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: m.isDeleted || m.isProduct || m.isTransfer
                                                          ? AppColors.textMuted
                                                          : (m.mine ? Colors.white70 : AppColors.textMuted),
                                                    ),
                                                  ),
                                                  if (m.mine && !m.isDeleted) ...[
                                                    const SizedBox(width: 4),
                                                    Icon(
                                                      m.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                                                      size: 14,
                                                      color: m.isRead
                                                          ? (m.isProduct || m.isTransfer
                                                              ? const Color(0xFF38BDF8)
                                                              : const Color(0xFFBAE6FD))
                                                          : (m.isProduct || m.isTransfer
                                                              ? AppColors.textMuted
                                                              : Colors.white70),
                                                    ),
                                                  ],
                                                ],
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
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (conversation?.blocked == true)
                          Container(
                            width: double.infinity,
                            color: const Color(0xFFFEF2F2),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Text(
                              conversation?.iBlocked == true
                                  ? 'You blocked this user. Unblock to chat or transfer.'
                                  : 'Messaging is blocked with this user.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (replyingTo != null)
                          _ReplyingStrip(
                            message: replyingTo!,
                            onCancel: () => setState(() => replyingTo = null),
                          ),
                        if (pendingProduct != null)
                          _PendingProductStrip(
                            product: pendingProduct!,
                            sending: sendingProduct,
                            onSend: _sendPendingProduct,
                            onDismiss: () => setState(() => pendingProduct = null),
                          ),
                        if (recordingVoice)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Row(
                              children: [
                                const Icon(Icons.mic, color: AppColors.danger),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Recording… ${_formatRecord(recordSeconds)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _stopVoice(send: false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => _stopVoice(send: true),
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                                  child: const Text('Send'),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: showAttachPanel ? 'Close' : 'Attach',
                                onPressed: (sending ||
                                        uploadingMedia ||
                                        recordingVoice ||
                                        sendingProduct ||
                                        conversation?.blocked == true)
                                    ? null
                                    : _toggleAttachPanel,
                                style: IconButton.styleFrom(
                                  foregroundColor: AppColors.accent,
                                  disabledForegroundColor: AppColors.textMuted,
                                ),
                                icon: uploadingMedia
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                      )
                                    : Icon(showAttachPanel ? Icons.close_rounded : Icons.add_circle_outline_rounded),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focus,
                                  minLines: 1,
                                  maxLines: 4,
                                  enabled: !uploadingMedia &&
                                      !recordingVoice &&
                                      conversation?.blocked != true,
                                  textInputAction: TextInputAction.send,
                                  onTap: () {
                                    if (showAttachPanel) setState(() => showAttachPanel = false);
                                  },
                                  decoration: InputDecoration(
                                    hintText: conversation?.blocked == true
                                        ? 'Chat blocked'
                                        : uploadingMedia
                                            ? 'Sending…'
                                            : recordingVoice
                                                ? 'Recording voice…'
                                                : 'Type a message…',
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
                                onPressed: (sending ||
                                        uploadingMedia ||
                                        recordingVoice ||
                                        conversation?.blocked == true)
                                    ? null
                                    : _send,
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
                        if (showAttachPanel)
                          _AttachPanel(
                            canCall: true,
                            onCamera: () => _sendPhoto(ImageSource.camera),
                            onAlbum: () => _sendPhoto(ImageSource.gallery),
                            onVideo: _sendVideo,
                            onVoice: _startVoice,
                            onAudioCall: () => unawaited(_startInAppCall(ChatCallKind.voice)),
                            onVideoCall: () => unawaited(_startInAppCall(ChatCallKind.video)),
                            onTransfer: _openTransfer,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
                if (_call != null)
                  ListenableBuilder(
                    listenable: _call!,
                    builder: (context, _) {
                      if (_call!.state == ChatCallState.idle) {
                        return const SizedBox.shrink();
                      }
                      return Positioned.fill(
                        child: ChatCallOverlay(
                          call: _call!,
                          peerName: conversation?.otherName ?? 'Chat',
                          onAccept: () => unawaited(_acceptInAppCall()),
                          onEnd: () => unawaited(_endInAppCall()),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }

  String _formatRecord(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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

/// Quoted product/text shown above a reply bubble.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.reply,
    required this.mine,
    required this.onOpenProduct,
  });

  final ChatReplyTo reply;
  final bool mine;
  final void Function(String slug) onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final photo = ApiConfig.resolveMediaUrl(reply.productImage);
    final product = reply.isProduct;

    return GestureDetector(
      onTap: product && (reply.productSlug ?? '').isNotEmpty
          ? () => onOpenProduct(reply.productSlug!)
          : null,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(product ? 8 : 0, product ? 8 : 0, product ? 8 : 0, 6),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withValues(alpha: 0.18) : const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: mine ? Colors.white70 : AppColors.accent, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reply.senderName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: mine ? Colors.white : AppColors.accent,
              ),
            ),
            const SizedBox(height: 4),
            if (product)
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: photo.isEmpty
                          ? ColoredBox(
                              color: AppColors.ringOrange,
                              child: const Icon(Icons.shopping_bag_outlined, size: 18, color: AppColors.accent),
                            )
                          : CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reply.productName ?? reply.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: mine ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                        if (reply.productPrice != null)
                          Text(
                            _money.format(reply.productPrice),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: mine ? Colors.white70 : AppColors.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            else
              Text(
                reply.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: mine ? Colors.white70 : AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReplyingStrip extends StatelessWidget {
  const _ReplyingStrip({required this.message, required this.onCancel});

  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final photo = ApiConfig.resolveMediaUrl(message.productImage);
    final label = message.isProduct
        ? (message.productName ?? 'Product')
        : message.isPhoto
            ? (message.body.trim().isEmpty ? 'Photo' : message.body.trim())
            : message.isVideo
                ? 'Video'
                : message.isVoice
                    ? 'Voice message'
                    : message.isTransfer
                        ? 'Money transfer'
                        : message.body;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        border: Border(bottom: BorderSide(color: Color(0xFFFFE0C2))),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 40, color: AppColors.accent),
          const SizedBox(width: 10),
          if (message.isProduct) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: photo.isEmpty
                    ? const ColoredBox(
                        color: Colors.white,
                        child: Icon(Icons.shopping_bag_outlined, color: AppColors.accent),
                      )
                    : CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.isProduct
                      ? 'Replying to product'
                      : 'Replying to message',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.accent),
                ),
                const SizedBox(height: 2),
                Text(
                  message.isProduct ? (message.productName ?? label) : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (message.isProduct && message.productPrice != null)
                  Text(
                    _money.format(message.productPrice),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.accent),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Product waiting above the composer — buyer taps Send to share it.
class _PendingProductStrip extends StatelessWidget {
  const _PendingProductStrip({
    required this.product,
    required this.sending,
    required this.onSend,
    required this.onDismiss,
  });

  final AttachProduct product;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final photo = ApiConfig.resolveMediaUrl(product.imageUrl);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        border: Border(bottom: BorderSide(color: Color(0xFFFFE0C2))),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              color: Colors.white,
              child: photo.isEmpty
                  ? const Icon(Icons.shopping_bag_outlined, color: AppColors.accent)
                  : CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (product.price != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _money.format(product.price),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          FilledButton(
            onPressed: sending ? null : onSend,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(sending ? 'Sending…' : 'Send'),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: sending ? null : onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
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

/// In-thread product share card (sent when opening chat from product detail).
class _ChatProductCard extends StatelessWidget {
  const _ChatProductCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final slug = message.productSlug ?? '';
    final photo = ApiConfig.resolveMediaUrl(message.productImage);
    final price = message.productPrice;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: slug.isEmpty ? null : () => context.push('/products/$slug'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 64,
                  height: 64,
                  color: AppColors.background,
                  child: photo.isEmpty
                      ? const Icon(Icons.shopping_bag_outlined, color: AppColors.accent)
                      : CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.productName ?? message.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (price != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _money.format(price),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to view product',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wallet transfer bubble — amount always shown in GHS.
class _ChatTransferCard extends StatelessWidget {
  const _ChatTransferCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final amount = message.transferAmount;
    final note = (message.transferNote ?? '').trim();
    final ref = (message.transferReference ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF16A34A)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.mine ? 'You transferred' : 'Transfer received',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      amount == null ? 'GH₵—' : _money.format(amount),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(note, style: const TextStyle(color: AppColors.textPrimary, height: 1.3)),
          ],
          if (ref.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ref $ref',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
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

/// Alibaba-style attach grid sits under the composer, not as a sheet on the
/// navigation bar — so options stay visible and clear of system chrome.
class _AttachPanel extends StatelessWidget {
  const _AttachPanel({
    required this.canCall,
    required this.onCamera,
    required this.onAlbum,
    required this.onVideo,
    required this.onVoice,
    required this.onAudioCall,
    required this.onVideoCall,
    required this.onTransfer,
  });

  final bool canCall;
  final VoidCallback onCamera;
  final VoidCallback onAlbum;
  final VoidCallback onVideo;
  final VoidCallback onVoice;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final tiles = <_AttachTileData>[
      _AttachTileData('Camera', Icons.photo_camera_outlined, onCamera),
      _AttachTileData('Album', Icons.photo_library_outlined, onAlbum),
      _AttachTileData('Video', Icons.videocam_outlined, onVideo),
      _AttachTileData('Voice', Icons.mic_none_rounded, onVoice),
      if (canCall) ...[
        _AttachTileData('Audio', Icons.call_outlined, onAudioCall),
        _AttachTileData('Video call', Icons.video_call_outlined, onVideoCall),
      ],
      _AttachTileData('Transfer', Icons.swap_horiz_rounded, onTransfer),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.92,
        children: [
          for (final tile in tiles)
            InkWell(
              onTap: tile.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(tile.icon, color: AppColors.accent, size: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tile.label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AttachTileData {
  const _AttachTileData(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ChatVideo extends StatefulWidget {
  const _ChatVideo({required this.url, required this.mine});

  final String url;
  final bool mine;

  @override
  State<_ChatVideo> createState() => _ChatVideoState();
}

class _ChatVideoState extends State<_ChatVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final resolved = ApiConfig.resolveMediaUrl(widget.url);
    _controller = VideoPlayerController.networkUrl(Uri.parse(resolved))
      ..initialize().then((_) {
        if (!mounted) return;
        _controller?.setVolume(0);
        setState(() {});
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await showVideoViewer(context, url: widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized && !_failed;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _failed ? null : _open,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 220,
            height: 160,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  )
                else
                  ColoredBox(
                    color: widget.mine ? Colors.white24 : AppColors.background,
                    child: Center(
                      child: _failed
                          ? const Icon(Icons.videocam_off_outlined, color: AppColors.textMuted)
                          : const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                            ),
                    ),
                  ),
                if (!_failed)
                  Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap to play',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatVoice extends StatefulWidget {
  const _ChatVoice({
    required this.url,
    required this.durationLabel,
    required this.mine,
  });

  final String url;
  final String durationLabel;
  final bool mine;

  @override
  State<_ChatVoice> createState() => _ChatVoiceState();
}

class _ChatVoiceState extends State<_ChatVoice> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
      return;
    }
    final resolved = ApiConfig.resolveMediaUrl(widget.url);
    await _player.play(UrlSource(resolved));
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? Colors.white : AppColors.textPrimary;
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: fg, size: 34),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: widget.mine ? Colors.white54 : AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.durationLabel.isEmpty ? 'Voice message' : widget.durationLabel,
                  style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
