import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Login to chat with sellers', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: () => context.push('/login'), child: const Text('Login')),
          ],
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
      return const Center(
        child: Text('No conversations yet.\nMessage a seller from a product page.', textAlign: TextAlign.center),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: store.conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final c = store.conversations[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.ringOrange,
              child: Text(
                c.otherName.isNotEmpty ? c.otherName[0].toUpperCase() : 'S',
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
              ),
            ),
            title: Text(c.otherName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              c.latestBody?.isNotEmpty == true
                  ? c.latestBody!
                  : (c.productName ?? 'Conversation'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: c.unreadCount > 0
                ? CircleAvatar(
                    radius: 11,
                    backgroundColor: AppColors.accent,
                    child: Text('${c.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  )
                : null,
            onTap: () => context.push('/messages/${c.id}'),
          );
        },
      ),
    );
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
  List<ChatMessage> messages = [];
  String title = 'Chat';
  bool loading = true;
  bool sending = false;
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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppStore>().loadConversation(widget.conversationId);
      if (!mounted) return;
      setState(() {
        title = result.conversation.otherName;
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final msg = await context.read<AppStore>().sendMessage(widget.conversationId, text);
      _controller.clear();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: loading
          ? const FullPageLoader(label: 'Opening chat…')
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final m = messages[index];
                      return Align(
                        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: m.mine ? AppColors.accent : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: m.mine ? null : Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            m.body,
                            style: TextStyle(color: m.mine ? Colors.white : AppColors.textPrimary),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(hintText: 'Type a message…'),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: sending ? null : _send,
                          style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                          icon: const Icon(Icons.send, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
