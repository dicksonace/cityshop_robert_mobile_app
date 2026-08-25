import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:video_player/video_player.dart';

import '../../services/video_overlay.dart';
import '../../theme/app_theme.dart';
import 'image_draw_screen.dart';
import 'media_text_screen.dart';
import 'video_trim_screen.dart';

class ChatMediaDraft {
  ChatMediaDraft({
    required this.path,
    required this.filename,
    required this.isVideo,
    this.caption = '',
  });

  final String path;
  final String filename;
  final bool isVideo;
  String caption;
}

class MediaSendDraft {
  const MediaSendDraft({
    required this.path,
    required this.filename,
    required this.isVideo,
    required this.caption,
    required this.viewOnce,
  });

  final String path;
  final String filename;
  final bool isVideo;
  final String caption;
  final bool viewOnce;
}

/// WhatsApp-style multi media preview: swipe items, caption per item, optional view-once for all.
class MediaCaptionScreen extends StatefulWidget {
  const MediaCaptionScreen({
    super.key,
    required this.items,
    this.initialCaption = '',
  });

  MediaCaptionScreen.single({
    super.key,
    required String path,
    required bool isVideo,
    String filename = '',
    this.initialCaption = '',
  }) : items = [
          ChatMediaDraft(
            path: path,
            filename: filename.isNotEmpty ? filename : (isVideo ? 'chat.mp4' : 'chat.jpg'),
            isVideo: isVideo,
          ),
        ];

  final List<ChatMediaDraft> items;
  final String initialCaption;

  @override
  State<MediaCaptionScreen> createState() => _MediaCaptionScreenState();
}

class _MediaCaptionScreenState extends State<MediaCaptionScreen> {
  late final PageController _pageController;
  late final List<ChatMediaDraft> _items;
  late final TextEditingController _caption;
  VideoPlayerController? _video;
  bool viewOnce = false;
  bool videoReady = false;
  bool busy = false;
  int index = 0;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((item) {
      return ChatMediaDraft(
        path: item.path,
        filename: item.filename,
        isVideo: item.isVideo,
        caption: item.caption,
      );
    }).toList();
    if (_items.isNotEmpty && widget.initialCaption.trim().isNotEmpty) {
      _items.first.caption = widget.initialCaption.trim();
    }
    _caption = TextEditingController(text: _items.isEmpty ? '' : _items.first.caption);
    _pageController = PageController();
    _loadVideoFor(0);
  }

  @override
  void dispose() {
    _caption.dispose();
    _pageController.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _loadVideoFor(int i) async {
    await _video?.dispose();
    _video = null;
    videoReady = false;
    if (!mounted) return;
    setState(() {});

    if (i < 0 || i >= _items.length || !_items[i].isVideo) return;

    final controller = VideoPlayerController.file(File(_items[i].path))..setLooping(true);
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted || index != i) {
        await controller.dispose();
        if (_video == controller) _video = null;
        return;
      }
      setState(() => videoReady = true);
      await controller.play();
    } catch (_) {
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
    if (_items.length <= 1) {
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

  void _send() {
    _persistCaption();
    Navigator.pop(
      context,
      [
        for (final item in _items)
          MediaSendDraft(
            path: item.path,
            filename: item.filename,
            isVideo: item.isVideo,
            caption: item.caption.trim(),
            viewOnce: viewOnce,
          ),
      ],
    );
  }

  Future<void> _replaceCurrent({
    required String path,
    required String filename,
    required bool isVideo,
  }) async {
    final caption = _items[index].caption;
    setState(() {
      _items[index] = ChatMediaDraft(
        path: path,
        filename: filename,
        isVideo: isVideo,
        caption: caption,
      );
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
    if (!item.isVideo || busy) return;
    final trimmed = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => VideoTrimScreen(path: item.path)),
    );
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    await _replaceCurrent(
      path: trimmed,
      filename: 'chat_trim.mp4',
      isVideo: true,
    );
  }

  Future<void> _textCurrent() async {
    final item = _items[index];
    if (busy) return;
    final result = await Navigator.of(context).push<MediaTextResult>(
      MaterialPageRoute(
        builder: (_) => MediaTextScreen(path: item.path, isVideo: item.isVideo),
      ),
    );
    if (result == null || result.path.isEmpty || !mounted) return;

    if (!item.isVideo || !result.isOverlayOnly) {
      await _replaceCurrent(
        path: result.path,
        filename: 'chat_text.png',
        isVideo: false,
      );
      return;
    }

    setState(() => busy = true);
    try {
      final burned = await VideoOverlay.burnOverlay(
        videoPath: item.path,
        overlayPngPath: result.path,
      );
      if (!mounted) return;
      await _replaceCurrent(path: burned, filename: 'chat_text.mp4', isVideo: true);
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

  Future<void> _cropCurrent() async {
    final item = _items[index];
    if (item.isVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use Trim for videos.')),
      );
      return;
    }
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: item.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 92,
        maxWidth: 2048,
        maxHeight: 2048,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.accent,
            backgroundColor: Colors.black,
            dimmedLayerColor: const Color(0xCC000000),
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white54,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
            showCropGrid: true,
          ),
          IOSUiSettings(
            title: 'Crop',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            rotateButtonsHidden: false,
          ),
        ],
      );
      if (cropped == null || !mounted) return;
      await _replaceCurrent(
        path: cropped.path,
        filename: cropped.path.split('/').last.isNotEmpty
            ? cropped.path.split('/').last
            : 'chat_crop.jpg',
        isVideo: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not crop this photo')),
        );
      }
    }
  }

  Future<void> _drawCurrent() async {
    final item = _items[index];
    if (busy) return;
    final drawnPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImageDrawScreen(path: item.path, isVideo: item.isVideo),
      ),
    );
    if (drawnPath == null || drawnPath.isEmpty || !mounted) return;

    if (!item.isVideo) {
      await _replaceCurrent(path: drawnPath, filename: 'chat_draw.png', isVideo: false);
      return;
    }

    setState(() => busy = true);
    try {
      final burned = await VideoOverlay.burnOverlay(
        videoPath: item.path,
        overlayPngPath: drawnPath,
      );
      if (!mounted) return;
      await _replaceCurrent(path: burned, filename: 'chat_draw.mp4', isVideo: true);
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

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final total = _items.length;
    final current = _items[index];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
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
                      onPressed: busy ? null : _trimCurrent,
                      icon: const Icon(Icons.content_cut, color: Colors.white),
                    ),
                  if (!current.isVideo)
                    IconButton(
                      tooltip: 'Crop',
                      onPressed: busy ? null : _cropCurrent,
                      icon: const Icon(Icons.crop_rotate, color: Colors.white),
                    ),
                  IconButton(
                    tooltip: 'Text',
                    onPressed: busy ? null : _textCurrent,
                    icon: const Text(
                      'Aa',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Pen',
                    onPressed: busy ? null : _drawCurrent,
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  ),
                  if (total > 1)
                    IconButton(
                      tooltip: 'Remove this one',
                      onPressed: busy ? null : _removeCurrent,
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                ],
              ),
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
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: total,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) {
                final item = _items[i];
                if (item.isVideo) {
                  if (i != index) return const ColoredBox(color: Colors.black);
                  return Center(
                    child: videoReady && _video != null
                        ? AspectRatio(
                            aspectRatio: _video!.value.aspectRatio == 0 ? 9 / 16 : _video!.value.aspectRatio,
                            child: VideoPlayer(_video!),
                          )
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_rounded, color: Colors.white70, size: 72),
                              SizedBox(height: 12),
                              Text('Loading video…', style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                  );
                }
                return ClipRect(
                  child: Image.file(
                    File(item.path),
                    key: ValueKey(item.path),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    gaplessPlayback: false,
                  ),
                );
              },
            ),
          ),
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
                    onTap: () {
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                    children: [
                      Tooltip(
                        message: viewOnce ? 'View once on (all)' : 'View once (all)',
                        child: InkWell(
                          onTap: () => setState(() => viewOnce = !viewOnce),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: viewOnce ? AppColors.accent : Colors.white12,
                              border: Border.all(
                                color: viewOnce ? AppColors.accent : Colors.white54,
                                width: 1.5,
                              ),
                            ),
                            child: const Text(
                              '1',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _caption,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: AppColors.accent,
                          textInputAction: TextInputAction.send,
                          maxLines: 4,
                          minLines: 1,
                          maxLength: 500,
                          onChanged: (value) => _items[index].caption = value,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Add a caption…',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white12,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: busy ? null : _send,
                        style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                        icon: const Icon(Icons.send_rounded, color: Colors.white),
                      ),
                    ],
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
