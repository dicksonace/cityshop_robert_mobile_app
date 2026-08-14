import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';

class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _ChatWallpaperPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  const _ChatWallpaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ChatColors.wallpaper);
    final paint = Paint()
      ..color = ChatColors.doodle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;

    const step = 78.0;
    var i = 0;
    for (var y = -24.0; y < size.height + 48; y += step) {
      for (var x = -24.0; x < size.width + 48; x += step) {
        final stagger = (i.isEven ? 16.0 : 0.0);
        _drawDoodle(canvas, Offset(x + stagger, y), paint, i);
        i++;
      }
    }
  }

  void _drawDoodle(Canvas canvas, Offset origin, Paint paint, int i) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate((i % 7 - 3) * 0.18);
    switch (i % 8) {
      case 0:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 14, 10), const Radius.circular(3)),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4, 10)
            ..lineTo(6, 14)
            ..lineTo(8, 10),
          paint,
        );
      case 1:
        canvas.drawCircle(const Offset(7, 7), 6, paint);
        canvas.drawCircle(const Offset(7, 7), 2.2, paint);
      case 2:
        canvas.drawOval(const Rect.fromLTWH(2, 0, 10, 14), paint);
        canvas.drawLine(const Offset(7, 14), const Offset(7, 18), paint);
      case 3:
        canvas.drawPath(
          Path()
            ..moveTo(7, 13)
            ..cubicTo(0, 7, 2, 1, 7, 5)
            ..cubicTo(12, 1, 14, 7, 7, 13),
          paint,
        );
      case 4:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(1, 2, 12, 8), const Radius.circular(1.5)),
          paint,
        );
        canvas.drawLine(const Offset(4, 12), const Offset(10, 12), paint);
      case 5:
        canvas.drawArc(const Rect.fromLTWH(0, 2, 12, 12), math.pi * 0.15, math.pi * 1.4, false, paint);
        canvas.drawCircle(const Offset(10, 4), 1.4, paint);
      case 6:
        canvas.drawOval(const Rect.fromLTWH(0, 4, 14, 8), paint);
        canvas.drawLine(const Offset(4, 4), const Offset(4, 1), paint);
        canvas.drawLine(const Offset(10, 4), const Offset(10, 1), paint);
      default:
        canvas.drawCircle(const Offset(4, 8), 2.4, paint);
        canvas.drawCircle(const Offset(11, 8), 2.4, paint);
        canvas.drawLine(const Offset(6.2, 8), const Offset(8.8, 8), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ChatBubbleTail extends StatelessWidget {
  const ChatBubbleTail({super.key, required this.mine, required this.color});

  final bool mine;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(7, 10),
      painter: _BubbleTailPainter(mine: mine, color: color),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.mine, required this.color});

  final bool mine;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (mine) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, 0)
        ..lineTo(size.width, size.height);
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.mine != mine || oldDelegate.color != color;
  }
}
