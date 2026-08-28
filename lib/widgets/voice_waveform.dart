import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Normalizes mic dB from the record package into 0.08–1.0 bar height.
double normalizeVoiceAmplitudeDb(double db) {
  if (db.isNaN || db.isInfinite) return 0.1;
  const minDb = -50.0;
  const maxDb = -5.0;
  if (db <= minDb) return 0.1;
  if (db >= maxDb) return 1.0;
  return 0.1 + ((db - minDb) / (maxDb - minDb)) * 0.9;
}

/// Keeps waveform samples for playback (keyed by local path or remote URL).
class VoiceWaveformCache {
  VoiceWaveformCache._();

  static final VoiceWaveformCache instance = VoiceWaveformCache._();
  final _byKey = <String, List<double>>{};

  void put(String key, List<double> samples) {
    if (key.isEmpty || samples.isEmpty) return;
    _byKey[key] = List<double>.from(samples);
  }

  List<double>? get(String key) {
    if (key.isEmpty) return null;
    return _byKey[key];
  }

  void move(String from, String to) {
    if (from.isEmpty || to.isEmpty || from == to) return;
    final samples = _byKey.remove(from);
    if (samples != null) _byKey[to] = samples;
  }
}

class VoiceWaveform {
  VoiceWaveform._();

  static List<double> downsample(List<double> samples, {required int maxBars}) {
    if (samples.isEmpty) return const [];
    if (samples.length <= maxBars) return List<double>.from(samples);
    final out = <double>[];
    final chunk = samples.length / maxBars;
    for (var i = 0; i < maxBars; i++) {
      final start = (i * chunk).floor();
      final end = math.min(samples.length, ((i + 1) * chunk).ceil());
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        peak = math.max(peak, samples[j]);
      }
      out.add(peak);
    }
    return out;
  }

  static List<double> normalizeBars(List<double> samples, {required int barCount}) {
    if (samples.isEmpty) {
      return List<double>.filled(barCount, 0.12);
    }
    final resized = downsample(samples, maxBars: barCount);
    final maxVal = resized.reduce(math.max).clamp(0.001, 1.0);
    return resized.map((v) => (v / maxVal).clamp(0.08, 1.0)).toList();
  }

  static List<double> fallback({required int barCount, required int durationSeconds, String seed = ''}) {
    final hash = seed.isEmpty ? durationSeconds : seed.hashCode;
    final rand = math.Random(hash);
    return List<double>.generate(
      barCount,
      (i) => 0.12 + rand.nextDouble() * 0.55 + (i.isEven ? 0.08 : 0),
    );
  }
}

class VoiceWaveformBars extends StatelessWidget {
  const VoiceWaveformBars({
    super.key,
    required this.samples,
    this.progress,
    this.barCount = 36,
    this.height = 28,
    this.activeColor = const Color(0xFF111B21),
    this.inactiveColor = const Color(0xFF8696A0),
    this.playedColor,
    this.onSeek,
  });

  final List<double> samples;
  final double? progress;
  final int barCount;
  final double height;
  final Color activeColor;
  final Color inactiveColor;
  final Color? playedColor;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final bars = VoiceWaveform.normalizeBars(samples, barCount: barCount);
    final played = (progress ?? 0).clamp(0.0, 1.0);
    final playedFill = playedColor ?? activeColor.withValues(alpha: 0.45);

    Widget painter = CustomPaint(
      size: Size(double.infinity, height),
      painter: _VoiceWaveformPainter(
        bars: bars,
        progress: progress == null ? null : played,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        playedColor: playedFill,
      ),
    );

    if (onSeek != null) {
      painter = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seekFromLocal(d.localPosition.dx, context),
        onHorizontalDragUpdate: (d) => _seekFromLocal(d.localPosition.dx, context),
        child: painter,
      );
    }

    return SizedBox(height: height, child: painter);
  }

  void _seekFromLocal(double dx, BuildContext context) {
    if (onSeek == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    onSeek!( (dx / box.size.width).clamp(0.0, 1.0));
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  _VoiceWaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.playedColor,
  });

  final List<double> bars;
  final double? progress;
  final Color activeColor;
  final Color inactiveColor;
  final Color playedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0) return;
    const gap = 2.0;
    final barWidth = math.max(1.5, (size.width - gap * (bars.length - 1)) / bars.length);
    final playedIndex = progress == null ? -1.0 : progress! * bars.length;

    for (var i = 0; i < bars.length; i++) {
      final h = math.max(3.0, bars[i] * size.height);
      final x = i * (barWidth + gap);
      final y = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(999),
      );
      final paint = Paint()
        ..color = progress == null
            ? activeColor
            : (i <= playedIndex ? activeColor : playedColor);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor;
  }
}
