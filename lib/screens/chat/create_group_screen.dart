import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Create a group chat — available to buyers and sellers.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final nameCtrl = TextEditingController();
  final mobileCtrl = TextEditingController();
  final members = <Map<String, dynamic>>[];
  bool searching = false;
  bool creating = false;
  String? error;

  @override
  void dispose() {
    nameCtrl.dispose();
    mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
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
      if (id == me) {
        setState(() => error = 'You are already in the group');
        return;
      }
      if (members.any((m) => (m['id'] as num?)?.toInt() == id)) {
        setState(() => error = 'Already added');
        return;
      }
      setState(() {
        members.add(user);
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

  Future<void> _create() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Enter a group name');
      return;
    }
    if (members.isEmpty) {
      setState(() => error = 'Add at least one member');
      return;
    }
    setState(() {
      creating = true;
      error = null;
    });
    try {
      final ids = members.map((m) => (m['id'] as num).toInt()).toList();
      final opened = await context.read<AppStore>().createGroupChat(name: name, memberIds: ids);
      if (!mounted) return;
      context.pushReplacement('/messages/${opened.conversation.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Group name',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Family, Market friends',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Add members',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Search CityShop users by mobile. Buyers and sellers can both create groups.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: mobileCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addMember(),
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    hintText: 'e.g. 0244123456',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: searching ? null : _addMember,
                  child: searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add'),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AppColors.danger)),
          ],
          if (members.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '${members.length} member${members.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final member in members) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _Avatar(name: '${member['name'] ?? 'U'}', avatar: member['avatar'] as String?),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${member['name'] ?? 'CityShop user'}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${member['mobile'] ?? ''}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => setState(() => members.remove(member)),
                      icon: const Icon(Icons.close, color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: creating ? 'Creating…' : 'Create group',
            loading: creating,
            onPressed: creating ? null : _create,
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.avatar});

  final String name;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final url = ApiConfig.resolveMediaUrl(avatar);
    final initial = name.trim().isEmpty ? 'G' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.accent.withValues(alpha: 0.15),
      backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
      child: url.isEmpty
          ? Text(initial, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent))
          : null,
    );
  }
}
