/// Product listing video limits (must stay aligned with API `max:51200` KB).
class ProductVideoLimits {
  static const int maxBytes = 50 * 1024 * 1024; // 50 MiB
  static const int maxSeconds = 60;
  /// Leave headroom under PHP/multipart limits so 50MB claims don't die mid-upload.
  static const int warnBytes = 45 * 1024 * 1024;

  static String formatMb(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb < 10) return '${mb.toStringAsFixed(1)} MB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  static String? sizeError(int bytes) {
    if (bytes <= 0) {
      return 'Could not read video file size. Try exporting as MP4 and pick again.';
    }
    if (bytes > maxBytes) {
      return 'Video must be 50 MB or smaller. This file is ${formatMb(bytes)}.';
    }
    return null;
  }

  static String? durationError(double seconds) {
    if (!seconds.isFinite || seconds <= 0) {
      return 'Could not read video length. Use MP4/MOV under 1 minute.';
    }
    if (seconds > maxSeconds + 0.5) {
      final totalMs = (seconds * 1000).round();
      final m = totalMs ~/ 60000;
      final s = (totalMs % 60000) ~/ 1000;
      return 'Video must be 1 minute or less. This one is $m:${s.toString().padLeft(2, '0')}.';
    }
    return null;
  }
}
