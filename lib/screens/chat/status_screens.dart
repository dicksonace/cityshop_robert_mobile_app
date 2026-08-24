import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';

const _statusColors = [
  Color(0xFFEA580C),
  Color(0xFF7C3AED),
  Color(0xFF0F766E),
  Color(0xFFBE123C),
  Color(0xFF1D4ED8),
  Color(0xFF365314),
];

const _statusColorHex = [
  '#EA580C',
  '#7C3AED',
  '#0F766E',
  '#BE123C',
  '#1D4ED8',
  '#365314',
];

class StatusTray extends StatelessWidget {
  const StatusTray({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final feed = store.statusFeed;
    final me = store.user;
    final mine = feed?.mine;
    final others = feed?.users.where((b) => b.hasItems).toList() ?? const <StatusBundle>[];

    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          _StatusRing(
            name: 'My status',
            avatar: me?.avatar ?? mine?.user.avatar,
            unseen: false,
            mine: true,
            hasStatus: mine?.hasItems == true,
            onTap: () {
              if (mine != null && mine.hasItems) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StatusViewerScreen(bundle: mine, isMine: true)),
                );
              } else {
                _openComposer(context);
              }
            },
            onLongPress: () => _openComposer(context),
          ),
          for (final bundle in others)
            _StatusRing(
              name: bundle.user.name,
              avatar: bundle.user.avatar,
              unseen: bundle.hasUnseen,
              mine: false,
              hasStatus: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StatusViewerScreen(bundle: bundle, isMine: false)),
                );
              },
            ),
        ],
      ),
    );
  }
}

Future<void> _openComposer(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
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
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add status', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: AppColors.accent),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded, color: AppColors.accent),
              title: const Text('Text'),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == 'text') {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatusTextComposerScreen()),
    );
    return;
  }

  final file = await ImagePicker().pickImage(
    source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 85,
    maxWidth: 1600,
  );
  if (file == null || !context.mounted) return;

  try {
    await context.read<AppStore>().postStatus(
          imagePath: file.path,
          filename: file.name.isNotEmpty ? file.name : 'status.jpg',
        );
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _StatusRing extends StatelessWidget {
  const _StatusRing({
    required this.name,
    required this.onTap,
    this.avatar,
    this.unseen = false,
    this.mine = false,
    this.hasStatus = false,
    this.onLongPress,
  });

  final String name;
  final String? avatar;
  final bool unseen;
  final bool mine;
  final bool hasStatus;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final url = ApiConfig.resolveMediaUrl(avatar);
    final ringColor = !hasStatus
        ? AppColors.border
        : unseen
            ? AppColors.accent
            : const Color(0xFF9CA3AF);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor, width: 2.4),
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.ringOrange,
                      backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
                      child: url.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'S',
                              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
                            )
                          : null,
                    ),
                  ),
                  if (mine)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.add, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusTextComposerScreen extends StatefulWidget {
  const StatusTextComposerScreen({super.key});

  @override
  State<StatusTextComposerScreen> createState() => _StatusTextComposerScreenState();
}

class _StatusTextComposerScreenState extends State<StatusTextComposerScreen> {
  final _controller = TextEditingController();
  int colorIndex = 0;
  bool sending = false;

  Color get color => _statusColors[colorIndex % _statusColors.length];

  String get hex => _statusColorHex[colorIndex % _statusColorHex.length];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await context.read<AppStore>().postStatus(caption: text, backgroundColor: hex);
      if (mounted) Navigator.pop(context);
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
      backgroundColor: color,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Text status'),
        actions: [
          IconButton(
            tooltip: 'Change colour',
            onPressed: () => setState(() => colorIndex++),
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: 8,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Type a status',
                    hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: sending ? null : _post,
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: color),
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Post'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({super.key, required this.bundle, required this.isMine});

  final StatusBundle bundle;
  final bool isMine;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  late int index;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final firstUnseen = widget.bundle.items.indexWhere((item) => !item.viewed);
    index = firstUnseen >= 0 ? firstUnseen : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _markCurrent());
  }

  StatusItem? get current =>
      widget.bundle.items.isEmpty ? null : widget.bundle.items[index.clamp(0, widget.bundle.items.length - 1)];

  Future<void> _markCurrent() async {
    final item = current;
    if (item == null || widget.isMine || item.viewed) return;
    try {
      await context.read<AppStore>().viewStatus(item.id);
      await context.read<AppStore>().loadStatusFeed();
    } catch (_) {}
  }

  void _step(int delta) {
    final next = index + delta;
    if (next < 0 || next >= widget.bundle.items.length) {
      Navigator.pop(context);
      return;
    }
    setState(() => index = next);
    _markCurrent();
  }

  Future<void> _delete() async {
    final item = current;
    if (item == null) return;
    setState(() => busy = true);
    try {
      await context.read<AppStore>().deleteStatus(item.id);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = current;
    final media = ApiConfig.resolveMediaUrl(item?.mediaUrl);
    final bg = _parseHex(item?.backgroundColor) ?? Colors.black;

    return Scaffold(
      backgroundColor: bg,
      body: item == null
          ? const Center(child: Text('No status', style: TextStyle(color: Colors.white)))
          : Stack(
              fit: StackFit.expand,
              children: [
                if (item.isImage && media.isNotEmpty)
                  CachedNetworkImage(imageUrl: media, fit: BoxFit.contain)
                else
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        item.body ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(child: GestureDetector(onTap: () => _step(-1), behavior: HitTestBehavior.opaque)),
                    Expanded(child: GestureDetector(onTap: () => _step(1), behavior: HitTestBehavior.opaque)),
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < widget.bundle.items.length; i++)
                              Expanded(
                                child: Container(
                                  height: 3,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: i <= index ? Colors.white : Colors.white24,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close, color: Colors.white),
                            ),
                            CircleAvatar(
                              radius: 16,
                              backgroundImage: ApiConfig.resolveMediaUrl(widget.bundle.user.avatar).isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      ApiConfig.resolveMediaUrl(widget.bundle.user.avatar),
                                    )
                                  : null,
                              child: ApiConfig.resolveMediaUrl(widget.bundle.user.avatar).isEmpty
                                  ? Text(widget.bundle.user.name.isNotEmpty ? widget.bundle.user.name[0] : '?')
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.isMine ? 'My status' : widget.bundle.user.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (widget.isMine)
                              IconButton(
                                onPressed: busy ? null : _delete,
                                icon: const Icon(Icons.delete_outline, color: Colors.white),
                              ),
                          ],
                        ),
                        if (item.body != null && item.body!.trim().isNotEmpty && item.isImage) ...[
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              item.body!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

Color? _parseHex(String? value) {
  if (value == null || value.isEmpty) return null;
  var hex = value.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
