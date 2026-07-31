import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await context.read<AppStore>().loadNotifications();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'message':
      case 'call':
        return Icons.chat_bubble_outline;
      case 'new_order':
      case 'order':
      case 'order_status':
        return Icons.inventory_2_outlined;
      case 'payment':
        return Icons.payments_outlined;
      case 'admin_message':
      case 'dispute':
        return Icons.shield_outlined;
      case 'product_out_of_stock':
        return Icons.warning_amber_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _timeLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(dt);
    } catch (_) {
      return '';
    }
  }

  Future<void> _open(AppNotificationItem n) async {
    final store = context.read<AppStore>();
    if (n.isUnread) {
      try {
        await store.markNotificationRead(n.id);
      } catch (_) {}
    }

    if (!mounted) return;
    if (n.conversationId != null) {
      context.push('/messages/${n.conversationId}');
      return;
    }
    if (n.orderId != null) {
      context.push('/orders/${n.orderId}');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.notifications;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (store.unreadNotifications > 0)
            TextButton(
              onPressed: () async {
                try {
                  await store.markAllNotificationsRead();
                } on ApiException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: !store.isLoggedIn
          ? Center(
              child: ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Login'),
              ),
            )
          : loading
              ? const FullPageLoader(label: 'Loading notifications…')
              : error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: items.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Icon(Icons.notifications_none, size: 56, color: AppColors.textMuted),
                                SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    'No notifications yet',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                ),
                                SizedBox(height: 6),
                                Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 32),
                                    child: Text(
                                      'Order updates, messages, refunds, and announcements will show up here.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.textSecondary),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final n = items[index];
                                return Material(
                                  color: n.isUnread ? const Color(0xFFFFF7ED) : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    onTap: () => _open(n),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: n.isUnread
                                              ? const Color(0xFFFDBA74)
                                              : AppColors.border,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: AppColors.ringOrange,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(_iconFor(n.type), color: AppColors.accent, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        n.title,
                                                        style: TextStyle(
                                                          fontWeight: n.isUnread
                                                              ? FontWeight.w900
                                                              : FontWeight.w700,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      _timeLabel(n.createdAt),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if ((n.body ?? '').trim().isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    n.body!,
                                                    style: const TextStyle(
                                                      color: AppColors.textSecondary,
                                                      height: 1.35,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (n.isUnread) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              width: 8,
                                              height: 8,
                                              margin: const EdgeInsets.only(top: 6),
                                              decoration: const BoxDecoration(
                                                color: AppColors.accent,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
    );
  }
}
