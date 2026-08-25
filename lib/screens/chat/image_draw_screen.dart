import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/app_theme.dart';

/// WhatsApp-style pen doodle on a photo. Pops the saved PNG path.
/// Captures only the photo bounds (no black letterbox / “space behind”).
class ImageDrawScreen extends StatefulWidget {
  const ImageDrawScreen({super.key, required this.path});

  final String path;

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
    _loadImageSize();
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
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Could not capture drawing');
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not encode drawing');

      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/chat_draw_${DateTime.now().millisecondsSinceEpoch}.png');
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
            child: imageSize == null
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
