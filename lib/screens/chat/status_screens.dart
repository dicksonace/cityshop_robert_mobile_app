import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../services/media_cache.dart';
import '../../services/video_overlay.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_video_limits.dart';
import 'image_draw_screen.dart';
import 'media_text_screen.dart';
import 'video_trim_screen.dart';

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

const _maxStatusBatch = 10;

class StatusMediaDraft {
  StatusMediaDraft({
    required this.path,
    required this.filename,
    required this.isVideo,
  });

  final String path;
  final String filename;
  final bool isVideo;
  String caption = '';
}

bool _looksLikeVideo(XFile file) {
  final mime = (file.mimeType ?? '').toLowerCase();
  if (mime.startsWith('video/')) return true;
  final name = file.name.toLowerCase();
  final path = file.path.toLowerCase();
  const exts = ['.mp4', '.mov', '.m4v', '.webm', '.3gp', '.mkv'];
  return exts.any((ext) => name.endsWith(ext) || path.endsWith(ext));
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
              leading: const Icon(Icons.collections_outlined, color: AppColors.accent),
              title: const Text('Photos & videos'),
              subtitle: const Text('Select several — each becomes its own status'),
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

  final picker = ImagePicker();
  List<XFile> picked = const [];

  if (choice == 'camera') {
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file != null) picked = [file];
  } else {
    picked = await picker.pickMultipleMedia(
      imageQuality: 85,
      maxWidth: 1600,
      limit: _maxStatusBatch,
    );
  }

  if (picked.isEmpty || !context.mounted) return;

  final drafts = <StatusMediaDraft>[];
  for (final file in picked.take(_maxStatusBatch)) {
    final isVideo = _looksLikeVideo(file);
    if (isVideo) {
      final sizeError = ProductVideoLimits.sizeError(await File(file.path).length());
      if (sizeError != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sizeError)));
        }
        continue;
      }
    }
    drafts.add(
      StatusMediaDraft(
        path: file.path,
        filename: file.name.isNotEmpty ? file.name : (isVideo ? 'status.mp4' : 'status.jpg'),
        isVideo: isVideo,
      ),
    );
  }

  if (drafts.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => StatusMediaComposerScreen(items: drafts)),
  );
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

class StatusMediaComposerScreen extends StatefulWidget {
  const StatusMediaComposerScreen({super.key, required this.items});

  final List<StatusMediaDraft> items;

  @override
  State<StatusMediaComposerScreen> createState() => _StatusMediaComposerScreenState();
}

class _StatusMediaComposerScreenState extends State<StatusMediaComposerScreen> {
  late final PageController _pageController;
  late final List<StatusMediaDraft> _items;
  final _caption = TextEditingController();
  final _focus = FocusNode();
  VideoPlayerController? _video;
  int index = 0;
  bool sending = false;
  bool videoReady = false;
  bool busy = false;
  int? postingIndex;

  @override
  void initState() {
    super.initState();
    _items = List<StatusMediaDraft>.from(widget.items);
    _pageController = PageController();
    _caption.text = _items.first.caption;
    _loadVideoFor(0);
  }

  @override
  void dispose() {
    _caption.dispose();
    _focus.dispose();
    _video?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadVideoFor(int i) async {
    await _video?.dispose();
    _video = null;
    videoReady = false;
    if (!mounted) return;
    setState(() {});

    final item = _items[i];
    if (!item.isVideo) return;

    final file = File(item.path);
    if (!await file.exists()) {
      if (mounted && index == i) setState(() => videoReady = false);
      return;
    }

    final controller = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..setLooping(true);
    _video = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || index != i) {
        await controller.dispose();
        if (_video == controller) _video = null;
        return;
      }
      setState(() => videoReady = true);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (_video == controller) _video = null;
      if (mounted && index == i) setState(() => videoReady = false);
    }
  }

  void _persistCaption() {
    if (_items.isEmpty) return;
    _items[index].caption = _caption.text;
  }

  void _onPageChanged(int i) {
    _persistCaption();
    setState(() {
      index = i;
      _caption.text = _items[i].caption;
    });
    _loadVideoFor(i);
  }

  void _removeCurrent() {
    if (_items.length <= 1 || sending) {
      Navigator.pop(context);
      return;
    }
    _persistCaption();
    setState(() {
      _items.removeAt(index);
      if (index >= _items.length) index = _items.length - 1;
      _caption.text = _items[index].caption;
    });
    _pageController.jumpToPage(index);
    _loadVideoFor(index);
  }

  Future<void> _replaceCurrent({
    required String path,
    required String filename,
    required bool isVideo,
  }) async {
    final caption = _items[index].caption;
    setState(() {
      _items[index] = StatusMediaDraft(
        path: path,
        filename: filename,
        isVideo: isVideo,
      )..caption = caption;
    });
    if (isVideo) {
      await _loadVideoFor(index);
    } else {
      await _video?.dispose();
      _video = null;
      videoReady = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _trimCurrent() async {
    final item = _items[index];
    if (!item.isVideo || busy || sending) return;
    final trimmed = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => VideoTrimScreen(path: item.path)),
    );
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    await _replaceCurrent(path: trimmed, filename: 'status_trim.mp4', isVideo: true);
  }

  Future<void> _textCurrent() async {
    final item = _items[index];
    if (busy || sending) return;
    final result = await Navigator.of(context).push<MediaTextResult>(
      MaterialPageRoute(
        builder: (_) => MediaTextScreen(path: item.path, isVideo: item.isVideo),
      ),
    );
    if (result == null || result.path.isEmpty || !mounted) return;
    if (!item.isVideo || !result.isOverlayOnly) {
      await _replaceCurrent(path: result.path, filename: 'status_text.png', isVideo: false);
      return;
    }
    setState(() => busy = true);
    try {
      final burned = await VideoOverlay.burnOverlay(
        videoPath: item.path,
        overlayPngPath: result.path,
      );
      if (!mounted) return;
      await _replaceCurrent(path: burned, filename: 'status_text.mp4', isVideo: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add text to this video')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _drawCurrent() async {
    final item = _items[index];
    if (busy || sending) return;
    final drawnPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImageDrawScreen(path: item.path, isVideo: item.isVideo),
      ),
    );
    if (drawnPath == null || drawnPath.isEmpty || !mounted) return;
    if (!item.isVideo) {
      await _replaceCurrent(path: drawnPath, filename: 'status_draw.png', isVideo: false);
      return;
    }
    setState(() => busy = true);
    try {
      final burned = await VideoOverlay.burnOverlay(
        videoPath: item.path,
        overlayPngPath: drawnPath,
      );
      if (!mounted) return;
      await _replaceCurrent(path: burned, filename: 'status_draw.mp4', isVideo: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add drawing to this video')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _post() async {
    if (sending || _items.isEmpty) return;
    _persistCaption();
    setState(() {
      sending = true;
      postingIndex = 0;
    });
    final store = context.read<AppStore>();
    try {
      for (var i = 0; i < _items.length; i++) {
        if (!mounted) return;
        setState(() => postingIndex = i);
        final item = _items[i];
        final caption = item.caption.trim();
        final last = i == _items.length - 1;
        if (item.isVideo) {
          await store.postStatus(
            videoPath: item.path,
            filename: item.filename,
            caption: caption.isEmpty ? null : caption,
            refreshFeed: last,
          );
        } else {
          await store.postStatus(
            imagePath: item.path,
            filename: item.filename,
            caption: caption.isEmpty ? null : caption,
            refreshFeed: last,
          );
        }
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
          postingIndex = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.length;
    final current = _items[index];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: sending ? null : _onPageChanged,
            physics: sending ? const NeverScrollableScrollPhysics() : null,
            itemBuilder: (context, i) {
              final item = _items[i];
              if (item.isVideo) {
                if (i != index) {
                  return const ColoredBox(color: Colors.black);
                }
                return Center(
                  child: videoReady && _video != null
                      ? AspectRatio(
                          aspectRatio: _video!.value.aspectRatio == 0 ? 9 / 16 : _video!.value.aspectRatio,
                          child: VideoPlayer(_video!),
                        )
                      : const CircularProgressIndicator(color: Colors.white54),
                );
              }
              return Image.file(
                File(item.path),
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: sending ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          busy
                              ? 'Applying…'
                              : total > 1
                                  ? '${index + 1} of $total'
                                  : (current.isVideo ? 'Video' : 'Photo'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (current.isVideo)
                        IconButton(
                          tooltip: 'Trim',
                          onPressed: sending || busy ? null : _trimCurrent,
                          icon: const Icon(Icons.content_cut, color: Colors.white),
                        ),
                      IconButton(
                        tooltip: 'Text',
                        onPressed: sending || busy ? null : _textCurrent,
                        icon: const Text(
                          'Aa',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Pen',
                        onPressed: sending || busy ? null : _drawCurrent,
                        icon: const Icon(Icons.edit_outlined, color: Colors.white),
                      ),
                      if (total > 1)
                        IconButton(
                          tooltip: 'Remove this one',
                          onPressed: sending || busy ? null : _removeCurrent,
                          icon: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                    ],
                  ),
                ),
                if (total > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Row(
                      children: [
                        for (var i = 0; i < total; i++)
                          Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: i == index ? Colors.white : Colors.white24,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (total > 1)
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: total,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final selected = i == index;
                        return GestureDetector(
                          onTap: sending
                              ? null
                              : () {
                                  _pageController.animateToPage(
                                    i,
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  );
                                },
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected ? AppColors.accent : Colors.white38,
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: item.isVideo
                                ? const ColoredBox(
                                    color: Color(0xFF111827),
                                    child: Icon(Icons.play_circle_outline, color: Colors.white70),
                                  )
                                : Image.file(File(item.path), fit: BoxFit.cover),
                          ),
                        );
                      },
                    ),
                  ),
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (total > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            'Caption for this ${current.isVideo ? 'video' : 'photo'} (optional)',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _caption,
                              focusNode: _focus,
                              enabled: !sending,
                              maxLines: 4,
                              minLines: 1,
                              maxLength: 500,
                              onChanged: (value) => _items[index].caption = value,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                              cursorColor: AppColors.accent,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: 'Add a caption...',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontWeight: FontWeight.w600,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.12),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: AppColors.accent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: sending ? null : _post,
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: Center(
                                  child: sending
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                        )
                                      : const Icon(Icons.send_rounded, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (sending && postingIndex != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Posting ${postingIndex! + 1} of $total…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
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

class _StatusViewerScreenState extends State<StatusViewerScreen> with SingleTickerProviderStateMixin {
  static const _imageHold = Duration(seconds: 5);

  late int index;
  late final AnimationController _progress;
  bool busy = false;
  bool paused = false;
  double videoProgress = 0;
  int viewCount = 0;
  List<StatusViewerEntry> viewers = const [];
  bool loadingViews = false;

  @override
  void initState() {
    super.initState();
    final firstUnseen = widget.bundle.items.indexWhere((item) => !item.viewed);
    index = firstUnseen >= 0 ? firstUnseen : 0;
    _progress = AnimationController(vsync: this, duration: _imageHold)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _step(1);
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markCurrent();
      _restartAutoAdvance();
      if (widget.isMine) _refreshViews();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
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

  void _restartAutoAdvance() {
    _progress.stop();
    _progress.reset();
    videoProgress = 0;
    final item = current;
    if (item == null || paused) return;
    if (item.isVideo) {
      // Video player reports progress / completion.
      setState(() {});
      return;
    }
    _progress.duration = _imageHold;
    _progress.forward();
    setState(() {});
  }

  void _setPaused(bool value) {
    if (paused == value) return;
    setState(() => paused = value);
    final item = current;
    if (item == null) return;
    if (item.isVideo) {
      // Video pause handled via prop on player rebuild.
      return;
    }
    if (value) {
      _progress.stop();
    } else if (_progress.value < 1) {
      _progress.forward();
    }
  }

  void _step(int delta) {
    final next = index + delta;
    if (next < 0 || next >= widget.bundle.items.length) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      index = next;
      videoProgress = 0;
      paused = false;
    });
    _markCurrent();
    _restartAutoAdvance();
    if (widget.isMine) _refreshViews();
  }

  Future<void> _refreshViews() async {
    final item = current;
    if (!widget.isMine || item == null) return;
    setState(() {
      loadingViews = true;
      viewCount = item.viewCount ?? viewCount;
    });
    try {
      final page = await context.read<AppStore>().loadStatusViews(item.id);
      if (!mounted || current?.id != item.id) return;
      setState(() {
        viewCount = page.viewCount;
        viewers = page.viewers;
        loadingViews = false;
      });
    } catch (_) {
      if (!mounted || current?.id != item.id) return;
      setState(() => loadingViews = false);
    }
  }

  Future<void> _openViewersSheet() async {
    final item = current;
    if (item == null) return;
    if (viewers.isEmpty && !loadingViews) {
      await _refreshViews();
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  viewCount == 1 ? '1 view' : '$viewCount views',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                if (loadingViews)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  )
                else if (viewers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No views yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: viewers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final viewer = viewers[i];
                        final avatar = ApiConfig.resolveMediaUrl(viewer.avatar);
                        final viewedAt = viewer.viewedAt;
                        final when = viewedAt == null
                            ? ''
                            : DateFormat('d MMM, h:mm a').format(DateTime.parse(viewedAt).toLocal());
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                            child: avatar.isEmpty
                                ? Text(viewer.name.isNotEmpty ? viewer.name[0].toUpperCase() : '?')
                                : null,
                          ),
                          title: Text(viewer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: when.isNotEmpty
                              ? Text(when, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
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

  double _segmentFill(int i) {
    if (i < index) return 1;
    if (i > index) return 0;
    final item = current;
    if (item != null && item.isVideo) return videoProgress.clamp(0.0, 1.0);
    return _progress.value.clamp(0.0, 1.0);
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
                if (item.isVideo && media.isNotEmpty)
                  _StatusVideoPlayer(
                    key: ValueKey('status-video-${item.id}'),
                    url: media,
                    paused: paused,
                    onProgress: (value) {
                      if (!mounted || paused) return;
                      setState(() => videoProgress = value);
                    },
                    onCompleted: () {
                      if (!mounted || paused) return;
                      _step(1);
                    },
                  )
                else if (item.isImage && media.isNotEmpty)
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
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _step(-1),
                        onLongPressStart: (_) => _setPaused(true),
                        onLongPressEnd: (_) => _setPaused(false),
                        behavior: HitTestBehavior.opaque,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _step(1),
                        onLongPressStart: (_) => _setPaused(true),
                        onLongPressEnd: (_) => _setPaused(false),
                        behavior: HitTestBehavior.opaque,
                      ),
                    ),
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) {
                            return Row(
                              children: [
                                for (var i = 0; i < widget.bundle.items.length; i++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(99),
                                        child: LinearProgressIndicator(
                                          value: _segmentFill(i),
                                          minHeight: 3,
                                          backgroundColor: Colors.white24,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
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
                      ],
                    ),
                  ),
                ),
                if ((item.body != null &&
                        item.body!.trim().isNotEmpty &&
                        (item.isImage || item.isVideo)) ||
                    widget.isMine)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (item.body != null &&
                                item.body!.trim().isNotEmpty &&
                                (item.isImage || item.isVideo))
                              Container(
                                width: double.infinity,
                                margin: EdgeInsets.only(bottom: widget.isMine ? 12 : 0),
                                padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black54],
                                  ),
                                ),
                                child: Text(
                                  item.body!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                                  ),
                                ),
                              ),
                            if (widget.isMine)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Material(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(999),
                                  child: InkWell(
                                    onTap: loadingViews ? null : _openViewersSheet,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            viewCount == 1 ? '1 view' : '$viewCount views',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (loadingViews) ...[
                                            const SizedBox(width: 10),
                                            const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StatusVideoPlayer extends StatefulWidget {
  const _StatusVideoPlayer({
    super.key,
    required this.url,
    this.paused = false,
    this.onCompleted,
    this.onProgress,
  });

  final String url;
  final bool paused;
  final VoidCallback? onCompleted;
  final ValueChanged<double>? onProgress;

  @override
  State<_StatusVideoPlayer> createState() => _StatusVideoPlayerState();
}

class _StatusVideoPlayerState extends State<_StatusVideoPlayer> {
  VideoPlayerController? _controller;
  bool ready = false;
  bool failed = false;
  bool downloading = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final file = await MediaCache.fileFor(widget.url);
      if (!mounted) return;
      final controller = VideoPlayerController.file(File(file.path))..setLooping(false);
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(_onTick);
      setState(() {
        ready = true;
        downloading = false;
      });
      if (!widget.paused) {
        await controller.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          downloading = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant _StatusVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (!ready || failed || controller == null) return;
    if (widget.paused && !oldWidget.paused) {
      controller.pause();
    } else if (!widget.paused && oldWidget.paused) {
      controller.play();
    }
  }

  void _onTick() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration.inMilliseconds <= 0) return;
    final progress = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    widget.onProgress?.call(progress);
    if (!_completed && position >= duration - const Duration(milliseconds: 200)) {
      _completed = true;
      widget.onCompleted?.call();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onTick);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 48),
            SizedBox(height: 12),
            Text('Could not play this video', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (!ready || _controller == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            if (downloading) ...[
              const SizedBox(height: 12),
              const Text('Downloading…', style: TextStyle(color: Colors.white54)),
            ],
          ],
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio == 0 ? 9 / 16 : _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
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
