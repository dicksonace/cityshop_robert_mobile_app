import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
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

/// Alibaba-style chat settings: search history, delete chat, group members.
class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
    this.peerAvatar,
    this.peerId,
    this.storeSlug,
    this.isSeller = false,
    this.isGroup = false,
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
  final bool isGroup;
  final bool canComplain;
  final int? sellerId;
  final int? productId;

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  late String _name;
  String? _avatar;
  List<ChatParticipant> _members = [];
  bool _loading = false;
  bool _avatarBusy = false;

  int? get _complaintSellerId =>
      widget.sellerId ?? (widget.canComplain || widget.isSeller ? widget.peerId : null);

  @override
  void initState() {
    super.initState();
    _name = widget.peerName;
    _avatar = widget.peerAvatar;
    if (widget.isGroup) {
      _refreshGroup();
    }
  }

  Future<void> _refreshGroup() async {
    setState(() => _loading = true);
    try {
      final opened = await context.read<AppStore>().loadConversation(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _name = opened.conversation.otherName;
        _avatar = opened.conversation.otherAvatar;
        _members = opened.conversation.participants;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickGroupPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      final updated = await context.read<AppStore>().uploadGroupAvatar(
            widget.conversationId,
            picked.path,
            filename: picked.name,
          );
      if (!mounted) return;
      setState(() {
        _avatar = updated.otherAvatar;
        _members = updated.participants;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group photo updated')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _addMembers() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddGroupMembersScreen(
          conversationId: widget.conversationId,
          existingIds: _members.map((m) => m.id).toSet(),
        ),
      ),
    );
    if (added == true && mounted) await _refreshGroup();
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: Text('You will leave "$_name" and stop receiving messages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppStore>().leaveGroup(widget.conversationId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the group')),
      );
      context.go('/shop?tab=messages');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _blockBuyer(ChatParticipant member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block buyer?'),
        content: Text(
          'Block ${member.name} from messaging you and remove them from this group?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await context.read<AppStore>().blockGroupMember(
            widget.conversationId,
            member.id,
          );
      if (!mounted) return;
      setState(() {
        _members = updated.participants;
        _name = updated.otherName;
        _avatar = updated.otherAvatar;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.name} blocked and removed')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _removeMember(ChatParticipant member) async {
    final me = context.read<AppStore>().user?.id;
    if (member.id == me) {
      await _leaveGroup();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${member.name} from this group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await context.read<AppStore>().removeGroupMember(
            widget.conversationId,
            member.id,
          );
      if (!mounted) return;
      setState(() {
        _members = updated.participants;
        _name = updated.otherName;
        _avatar = updated.otherAvatar;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showComplaint = widget.canComplain && _complaintSellerId != null;
    final avatarUrl = ApiConfig.resolveMediaUrl(_avatar);
    final letter = _name.trim().isNotEmpty ? _name.trim()[0].toUpperCase() : 'G';
    final me = context.watch<AppStore>().user?.id;
    final amAdmin = _members.any((m) => m.id == me && m.isCreator);

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
                GestureDetector(
                  onTap: widget.isGroup && !_avatarBusy ? _pickGroupPhoto : null,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                        backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
                        child: avatarUrl.isEmpty
                            ? Text(
                                letter,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
                              )
                            : null,
                      ),
                      if (widget.isGroup)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: _avatarBusy
                                ? const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                      if (widget.isGroup) ...[
                        const SizedBox(height: 2),
                        Text(
                          _loading
                              ? 'Loading members…'
                              : '${_members.isEmpty ? '…' : _members.length} members · Tap photo to change',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                if ((widget.storeSlug ?? '').trim().isNotEmpty)
                  IconButton(
                    tooltip: 'Store',
                    onPressed: () => context.push('/stores/${widget.storeSlug!.trim()}'),
                    icon: const Icon(Icons.storefront_outlined, color: AppColors.accent),
                  ),
              ],
            ),
          ),
          if (widget.isGroup) ...[
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Members',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addMembers,
                          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
                      child: Text(
                        'No members loaded yet.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  else
                    ..._members.map((m) {
                      final photo = ApiConfig.resolveMediaUrl(m.avatar);
                      final isMe = m.id == me;
                      final canRemove = amAdmin && !isMe && !m.isCreator;
                      final canBlock = canRemove && m.isBuyer;
                      final showMenu = isMe || canRemove;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.ringOrange,
                          backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
                          child: photo.isEmpty
                              ? Text(
                                  m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.accent,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(
                          isMe ? '${m.name} (You)' : m.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (m.isCreator) 'Admin',
                            m.presenceLabel,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: showMenu
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'remove') _removeMember(m);
                                  if (value == 'block') _blockBuyer(m);
                                  if (value == 'leave') _leaveGroup();
                                },
                                itemBuilder: (_) => [
                                  if (isMe)
                                    const PopupMenuItem(
                                      value: 'leave',
                                      child: Text('Leave group'),
                                    ),
                                  if (canRemove)
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove from group'),
                                    ),
                                  if (canBlock)
                                    const PopupMenuItem(
                                      value: 'block',
                                      child: Text('Block buyer'),
                                    ),
                                ],
                              )
                            : null,
                      );
                    }),
                ],
              ),
            ),
          ],
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
                        conversationId: widget.conversationId,
                        peerName: _name,
                      ),
                    ),
                  );
                },
              ),
              if (widget.isGroup)
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  label: 'Leave group',
                  destructive: true,
                  onTap: _leaveGroup,
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
                          sellerName: _name,
                          productId: widget.productId,
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
        title: Text(widget.isGroup ? 'Delete group chat?' : 'Delete chat?'),
        content: Text(
          widget.isGroup
              ? 'This removes "$_name" from your inbox. You stay in the group until you leave.'
              : 'This removes the chat with $_name from your inbox. You can still message them later.',
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
      await context.read<AppStore>().deleteConversation(widget.conversationId);
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

class AddGroupMembersScreen extends StatefulWidget {
  const AddGroupMembersScreen({
    super.key,
    required this.conversationId,
    required this.existingIds,
  });

  final int conversationId;
  final Set<int> existingIds;

  @override
  State<AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends State<AddGroupMembersScreen> {
  final mobileCtrl = TextEditingController();
  final toAdd = <Map<String, dynamic>>[];
  bool searching = false;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final value = mobileCtrl.text.trim();
    if (value.isEmpty) {
      setState(() => error = 'Enter a mobile number registered on CityShop');
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final user = await context.read<AppStore>().lookupUserByMobile(value);
      if (!mounted) return;
      if (user == null) {
        setState(() => error = 'No CityShop account found for that number');
        return;
      }
      final id = (user['id'] as num?)?.toInt();
      final me = context.read<AppStore>().user?.id;
      if (id == null) {
        setState(() => error = 'Invalid user');
        return;
      }
      if (id == me || widget.existingIds.contains(id)) {
        setState(() => error = 'Already in the group');
        return;
      }
      if (toAdd.any((m) => (m['id'] as num?)?.toInt() == id)) {
        setState(() => error = 'Already added');
        return;
      }
      setState(() {
        toAdd.add(user);
        mobileCtrl.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _save() async {
    if (toAdd.isEmpty) {
      setState(() => error = 'Add at least one member');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final ids = toAdd.map((m) => (m['id'] as num).toInt()).toList();
      await context.read<AppStore>().addGroupMembers(widget.conversationId, ids);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add members')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Search by mobile number to add people to this group.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: mobileCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Mobile number',
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: searching ? null : _lookup,
                child: searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Add'),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          ...toAdd.map((m) {
            final name = m['name'] as String? ?? 'User';
            final mobile = m['mobile'] as String? ?? '';
            final avatar = ApiConfig.resolveMediaUrl(m['avatar'] as String?);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                child: avatar.isEmpty
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                    : null,
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(mobile),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => toAdd.remove(m)),
              ),
            );
          }),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: saving || toAdd.isEmpty ? null : _save,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(toAdd.isEmpty ? 'Add people first' : 'Add ${toAdd.length} member${toAdd.length == 1 ? '' : 's'}'),
            ),
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
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
      trailing: Icon(Icons.chevron_right, color: destructive ? AppColors.danger : AppColors.textMuted),
      onTap: onTap,
    );
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
      final msgs = await context.read<AppStore>().searchMessages(
            widget.conversationId,
            q,
          );
      if (!mounted) return;
      setState(() => results = msgs);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Search · ${widget.peerName}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search messages',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: _search,
            ),
          ),
          if (searching) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error!, style: const TextStyle(color: AppColors.danger)),
            ),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('No matches', style: TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final m = results[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(m.body, style: const TextStyle(height: 1.35)),
                      );
                    },
                  ),
          ),
        ],
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
