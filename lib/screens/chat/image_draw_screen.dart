import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

/// WhatsApp-style pen doodle on a photo or video.
/// Photos: pops a baked PNG path.
/// Videos: pops a transparent overlay PNG path (burn with [VideoOverlay]).
class ImageDrawScreen extends StatefulWidget {
  const ImageDrawScreen({
    super.key,
    required this.path,
    this.isVideo = false,
  });

  final String path;
  final bool isVideo;

  @override
  State<ImageDrawScreen> createState() => _ImageDrawScreenState();
}

class _Stroke {
  _Stroke({required this.color, required this.width});

  final Color color;
  final double width;
  final List<Offset> points = [];
}

class _ImageDrawScreenState extends State<ImageDrawScreen> {
  final _boundaryKey = GlobalKey();
  final List<_Stroke> _strokes = [];
  _Stroke? _current;
  Color _color = const Color(0xFFFF3B30);
  double _width = 6;
  bool _saving = false;
  Size? _imageSize;
  VideoPlayerController? _video;
  bool _videoReady = false;

  static const _palette = [
    Color(0xFFFF3B30),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF007AFF),
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    } else {
      _loadImageSize();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
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
        _imageSize = c.value.size;
      });
    } catch (_) {
      if (mounted) setState(() => _imageSize = const Size(1080, 1920));
    }
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _imageSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      });
      frame.image.dispose();
    } catch (_) {
      if (mounted) setState(() => _imageSize = const Size(1080, 1920));
    }
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/chat_draw_${DateTime.now().millisecondsSinceEpoch}.png');

      if (widget.isVideo) {
        final size = _imageSize ?? const Size(1080, 1920);
        final w = size.width.round().clamp(2, 4096);
        final h = size.height.round().clamp(2, 4096);
        final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
        final previewW = box?.size.width ?? size.width;
        final previewH = box?.size.height ?? size.height;
        final sx = w / previewW;
        final sy = h / previewH;

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final stroke in _strokes) {
          if (stroke.points.isEmpty) continue;
          final paint = Paint()
            ..color = stroke.color
            ..strokeWidth = stroke.width * sx
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          if (stroke.points.length == 1) {
            canvas.drawCircle(
              Offset(stroke.points.first.dx * sx, stroke.points.first.dy * sy),
              stroke.width * sx / 2,
              paint..style = PaintingStyle.fill,
            );
            continue;
          }
          final path = Path()
            ..moveTo(stroke.points.first.dx * sx, stroke.points.first.dy * sy);
          for (var i = 1; i < stroke.points.length; i++) {
            path.lineTo(stroke.points[i].dx * sx, stroke.points[i].dy * sy);
          }
          canvas.drawPath(path, paint);
        }
        final image = await recorder.endRecording().toImage(w, h);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) throw StateError('encode');
        await out.writeAsBytes(bytes.buffer.asUint8List());
        if (!mounted) return;
        Navigator.pop(context, out.path);
        return;
      }

      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Could not capture drawing');
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not encode drawing');
      await out.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      Navigator.pop(context, out.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save drawing')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _imageSize;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Draw'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _strokes.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: _strokes.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
          TextButton(
            onPressed: _saving || imageSize == null ? null : _save,
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
            child: imageSize == null || (widget.isVideo && !_videoReady)
                ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final fitted = applyBoxFit(BoxFit.contain, imageSize, constraints.biggest);
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
                                  if (widget.isVideo && _video != null)
                                    FittedBox(
                                      fit: BoxFit.fill,
                                      child: SizedBox(
                                        width: _video!.value.size.width,
                                        height: _video!.value.size.height,
                                        child: VideoPlayer(_video!),
                                      ),
                                    )
                                  else
                                    Image.file(
                                      File(widget.path),
                                      fit: BoxFit.fill,
                                      filterQuality: FilterQuality.medium,
                                    ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanStart: (details) {
                                      setState(() {
                                        _current = _Stroke(color: _color, width: _width)
                                          ..points.add(details.localPosition);
                                        _strokes.add(_current!);
                                      });
                                    },
                                    onPanUpdate: (details) {
                                      setState(() => _current?.points.add(details.localPosition));
                                    },
                                    onPanEnd: (_) => _current = null,
                                    child: CustomPaint(painter: _StrokePainter(_strokes)),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              child: Row(
                children: [
                  for (final color in _palette)
                    GestureDetector(
                      onTap: () => setState(() => _color = color),
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
                  const Spacer(),
                  const Icon(Icons.line_weight, color: Colors.white70, size: 18),
                  SizedBox(
                    width: 110,
                    child: Slider(
                      value: _width,
                      min: 2,
                      max: 18,
                      activeColor: AppColors.accent,
                      onChanged: (v) => setState(() => _width = v),
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

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
