import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

class MediaTextResult {
  const MediaTextResult({
    required this.path,
    required this.isOverlayOnly,
  });

  /// For photos: baked composite image. For videos: transparent overlay PNG.
  final String path;
  final bool isOverlayOnly;
}

/// WhatsApp-style “Aa” text on a photo or video. Drag to place, tap Done to save.
class MediaTextScreen extends StatefulWidget {
  const MediaTextScreen({
    super.key,
    required this.path,
    required this.isVideo,
  });

  final String path;
  final bool isVideo;

  @override
  State<MediaTextScreen> createState() => _MediaTextScreenState();
}

class _TextBubble {
  _TextBubble({
    required this.controller,
    required this.focus,
    this.offset = const Offset(40, 120),
    this.color = Colors.white,
  });

  final TextEditingController controller;
  final FocusNode focus;
  Offset offset;
  Color color;
}

class _MediaTextScreenState extends State<MediaTextScreen> {
  final _boundaryKey = GlobalKey();
  final List<_TextBubble> _bubbles = [];
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _saving = false;
  Size? _mediaSize;
  Color _color = Colors.white;

  static const _palette = [
    Colors.white,
    Color(0xFFFF3B30),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF007AFF),
    Color(0xFF000000),
  ];

  @override
  void initState() {
    super.initState();
    _addBubble(autofocus: true);
    if (widget.isVideo) {
      _initVideo();
    } else {
      _loadImageSize();
    }
  }

  @override
  void dispose() {
    for (final b in _bubbles) {
      b.controller.dispose();
      b.focus.dispose();
    }
    _video?.dispose();
    super.dispose();
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _mediaSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      });
      frame.image.dispose();
    } catch (_) {
      if (mounted) setState(() => _mediaSize = const Size(1080, 1920));
    }
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(File(widget.path));
    _video = c;
    try {
      await c.initialize();
      await c.pause();
      if (!mounted) return;
      setState(() {
        _videoReady = true;
        _mediaSize = c.value.size;
      });
    } catch (_) {
      if (mounted) setState(() => _mediaSize = const Size(1080, 1920));
    }
  }

  void _addBubble({bool autofocus = false}) {
    final bubble = _TextBubble(
      controller: TextEditingController(),
      focus: FocusNode(),
      color: _color,
    );
    setState(() => _bubbles.add(bubble));
    if (autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) bubble.focus.requestFocus();
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final hasText = _bubbles.any((b) => b.controller.text.trim().isNotEmpty);
    if (!hasText) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/chat_text_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      if (widget.isVideo) {
        final size = _mediaSize ?? const Size(1080, 1920);
        final w = size.width.round().clamp(2, 4096);
        final h = size.height.round().clamp(2, 4096);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        // Transparent clear
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = const Color(0x00000000)..blendMode = BlendMode.clear,
        );

        // Map preview offsets to full media pixels.
        final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
        final previewW = box?.size.width ?? size.width;
        final previewH = box?.size.height ?? size.height;
        final sx = w / previewW;
        final sy = h / previewH;

        for (final bubble in _bubbles) {
          final text = bubble.controller.text.trim();
          if (text.isEmpty) continue;
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: bubble.color,
                fontSize: 28 * sx,
                fontWeight: FontWeight.w900,
                shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(bubble.offset.dx * sx, bubble.offset.dy * sy));
        }

        final image = await recorder.endRecording().toImage(w, h);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) throw StateError('encode');
        await out.writeAsBytes(bytes.buffer.asUint8List());
        if (!mounted) return;
        Navigator.pop(context, MediaTextResult(path: out.path, isOverlayOnly: true));
        return;
      }

      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('capture');
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('encode');
      await out.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      Navigator.pop(context, MediaTextResult(path: out.path, isOverlayOnly: false));
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save text')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _mediaSize;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Text'),
        actions: [
          IconButton(
            tooltip: 'Add text',
            onPressed: () => _addBubble(autofocus: true),
            icon: const Icon(Icons.text_fields),
          ),
          TextButton(
            onPressed: _saving || size == null ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: size == null || (widget.isVideo && !_videoReady)
                ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final fitted = applyBoxFit(BoxFit.contain, size, constraints.biggest);
                      final dest = fitted.destination;
                      return ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: SizedBox(
                            width: dest.width,
                            height: dest.height,
                            child: RepaintBoundary(
                              key: _boundaryKey,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (!widget.isVideo)
                                    Image.file(File(widget.path), fit: BoxFit.fill)
                                  else if (_video != null)
                                    FittedBox(
                                      fit: BoxFit.fill,
                                      child: SizedBox(
                                        width: _video!.value.size.width,
                                        height: _video!.value.size.height,
                                        child: VideoPlayer(_video!),
                                      ),
                                    ),
                                  for (var i = 0; i < _bubbles.length; i++)
                                    Positioned(
                                      left: _bubbles[i].offset.dx.clamp(0, dest.width - 40),
                                      top: _bubbles[i].offset.dy.clamp(0, dest.height - 40),
                                      child: GestureDetector(
                                        onPanUpdate: (d) {
                                          setState(() {
                                            _bubbles[i].offset += d.delta;
                                          });
                                        },
                                        child: IntrinsicWidth(
                                          child: TextField(
                                            controller: _bubbles[i].controller,
                                            focusNode: _bubbles[i].focus,
                                            style: TextStyle(
                                              color: _bubbles[i].color,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w900,
                                              shadows: const [
                                                Shadow(blurRadius: 6, color: Colors.black54),
                                              ],
                                            ),
                                            cursorColor: AppColors.accent,
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              border: InputBorder.none,
                                              hintText: 'Type…',
                                              hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800),
                                            ),
                                            onTap: () => setState(() => _color = _bubbles[i].color),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  for (final color in _palette)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _color = color;
                          for (final b in _bubbles) {
                            if (b.focus.hasFocus) b.color = color;
                          }
                          if (_bubbles.isNotEmpty && !_bubbles.any((b) => b.focus.hasFocus)) {
                            _bubbles.last.color = color;
                          }
                        });
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color ? AppColors.accent : Colors.white38,
                            width: _color == color ? 3 : 1,
                          ),
                        ),
                      ),
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
