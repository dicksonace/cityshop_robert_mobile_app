import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';

const _reportReasons = <({String value, String label})>[
  (value: 'scam', label: 'Scam or fraud'),
  (value: 'counterfeit', label: 'Counterfeit or fake products'),
  (value: 'harassment', label: 'Harassment or abuse'),
  (value: 'poor_service', label: 'Poor service or unresponsive seller'),
  (value: 'prohibited_items', label: 'Prohibited or illegal items'),
  (value: 'fake_listings', label: 'Misleading or fake listings'),
  (value: 'other', label: 'Other'),
];

/// Alibaba-style chat settings: search history, delete chat, make a complaint.
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
    this.peerAvatar,
    this.peerId,
    this.storeSlug,
    this.isSeller = false,
    this.canComplain = false,
    this.sellerId,
    this.productId,
  });

  final int conversationId;
  final String peerName;
  final String? peerAvatar;
  final int? peerId;
  final String? storeSlug;
  final bool isSeller;
  final bool canComplain;
  final int? sellerId;
  final int? productId;

  int? get _complaintSellerId => sellerId ?? (canComplain || isSeller ? peerId : null);

  @override
  Widget build(BuildContext context) {
    final showComplaint = canComplain && _complaintSellerId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Chat Settings', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                  backgroundImage: (peerAvatar ?? '').isNotEmpty ? NetworkImage(peerAvatar!) : null,
                  child: (peerAvatar ?? '').isEmpty
                      ? Text(
                          peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    peerName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                if ((storeSlug ?? '').trim().isNotEmpty)
                  IconButton(
                    tooltip: 'Store',
                    onPressed: () => context.push('/stores/${storeSlug!.trim()}'),
                    icon: const Icon(Icons.storefront_outlined, color: AppColors.accent),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.search_rounded,
                label: 'Search chat history',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatHistorySearchScreen(
                        conversationId: conversationId,
                        peerName: peerName,
                      ),
                    ),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                destructive: true,
                onTap: () => _confirmDelete(context),
              ),
              if (showComplaint)
                _SettingsTile(
                  icon: Icons.flag_outlined,
                  label: 'Make a complaint',
                  destructive: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatComplaintScreen(
                          sellerId: _complaintSellerId!,
                          sellerName: peerName,
                          productId: productId,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'This removes the chat with $peerName from your inbox. You can still message them later.',
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
    if (ok != true || !context.mounted) return;
    try {
      await context.read<AppStore>().deleteConversation(conversationId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted')),
      );
      context.go('/shop?tab=messages');
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class ChatHistorySearchScreen extends StatefulWidget {
  const ChatHistorySearchScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
  });

  final int conversationId;
  final String peerName;

  @override
  State<ChatHistorySearchScreen> createState() => _ChatHistorySearchScreenState();
}

class _ChatHistorySearchScreenState extends State<ChatHistorySearchScreen> {
  final _controller = TextEditingController();
  List<ChatMessage> results = [];
  bool searching = false;
  String? error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        results = [];
        error = null;
      });
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final found = await context.read<AppStore>().searchMessages(widget.conversationId, q);
      if (!mounted) return;
      setState(() {
        results = found;
        searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        searching = false;
        error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search chat history',
            border: InputBorder.none,
          ),
          onChanged: (v) {
            // Debounce lightly via microtask batching — search on submit is primary.
          },
          onSubmitted: _search,
        ),
        actions: [
          TextButton(
            onPressed: () => _search(_controller.text),
            child: searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Search'),
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!, style: const TextStyle(color: AppColors.danger)))
          : results.isEmpty
              ? Center(
                  child: Text(
                    _controller.text.trim().isEmpty
                        ? 'Type a keyword to search messages with ${widget.peerName}'
                        : searching
                            ? 'Searching…'
                            : 'No messages found',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final m = results[index];
                    return ListTile(
                      title: Text(
                        m.body.isEmpty ? m.eventLabel : m.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        m.mine ? 'You' : widget.peerName,
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
    );
  }
}

class ChatComplaintScreen extends StatefulWidget {
  const ChatComplaintScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    this.productId,
  });

  final int sellerId;
  final String sellerName;
  final int? productId;

  @override
  State<ChatComplaintScreen> createState() => _ChatComplaintScreenState();
}

class _ChatComplaintScreenState extends State<ChatComplaintScreen> {
  String reason = _reportReasons.first.value;
  final details = TextEditingController();
  bool submitting = false;

  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => submitting = true);
    try {
      await context.read<AppStore>().reportSeller(
            sellerId: widget.sellerId,
            reason: reason,
            details: details.text,
            productId: widget.productId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complaint submitted. Our team will review it.')),
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Make a complaint', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Report ${widget.sellerName} for review by CityShop admin.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('Reason', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: reason,
                isExpanded: true,
                items: [
                  for (final r in _reportReasons)
                    DropdownMenuItem(value: r.value, child: Text(r.label)),
                ],
                onChanged: submitting
                    ? null
                    : (v) {
                        if (v != null) setState(() => reason = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Details (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: details,
            maxLines: 5,
            maxLength: 2000,
            enabled: !submitting,
            decoration: InputDecoration(
              hintText: 'Tell us what happened…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Submit complaint'),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black26),
      onTap: onTap,
    );
  }
}
