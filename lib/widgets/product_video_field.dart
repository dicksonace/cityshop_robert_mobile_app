import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/api_config.dart';
import '../theme/app_theme.dart';
import '../utils/video_playback.dart';
import 'common_widgets.dart';
import 'product_video_limits.dart';

String formatVideoClock(Duration duration) {
  final total = duration.inSeconds.clamp(0, 24 * 60 * 60);
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Same preview height as the buyer product gallery (not full portrait video height).
double productVideoPreviewHeight(BuildContext context, double width) {
  final size = MediaQuery.sizeOf(context);
  final maxH = (size.height * 0.42).clamp(220.0, 320.0);
  return (width * 0.75).clamp(200.0, maxH);
}

/// Seller add/edit product video: plays the existing clip or a newly picked file.
class ProductVideoField extends StatefulWidget {
  const ProductVideoField({
    super.key,
    this.networkUrl,
    this.filePath,
    this.durationSeconds,
    this.fileSizeBytes,
    this.checking = false,
    this.error,
    required this.onPick,
    required this.onRemove,
  });

  final String? networkUrl;
  final String? filePath;
  final int? durationSeconds;
  final int? fileSizeBytes;
  final bool checking;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  State<ProductVideoField> createState() => _ProductVideoFieldState();
}

class _ProductVideoFieldState extends State<ProductVideoField> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _muted = false;
  int _loadToken = 0;

  bool get _hasSource {
    final file = widget.filePath;
    if (file != null && file.isNotEmpty) return true;
    return ApiConfig.resolveMediaUrl(widget.networkUrl).isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProductVideoField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath || oldWidget.networkUrl != widget.networkUrl) {
      _load();
    }
  }

  @override
  void deactivate() {
    _controller?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    _loadToken++;
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _controller = null;
    _ready = false;
    _failed = false;
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final previous = _controller;
    _controller = null;
    previous?.removeListener(_onTick);
    await previous?.dispose();
    if (!mounted || token != _loadToken) return;

    if (!_hasSource) {
      setState(() {
        _ready = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _ready = false;
      _failed = false;
    });
    VideoPlayerController? controller;
    try {
      final filePath = widget.filePath;
      controller = (filePath != null && filePath.isNotEmpty)
          ? VideoPlayerController.file(File(filePath))
          : VideoPlayerController.networkUrl(Uri.parse(ApiConfig.resolveMediaUrl(widget.networkUrl)));
      controller.addListener(_onTick);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted || token != _loadToken) {
        controller.removeListener(_onTick);
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _ready = true);
    } catch (_) {
      controller?.removeListener(_onTick);
      await controller?.dispose();
      if (!mounted || token != _loadToken) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !_ready) {
      await _load();
      return;
    }
    await toggleVideoPlayback(controller);
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _controller?.setVolume(_muted ? 0 : 1);
  }

  String _durationLabel() {
    final live = _controller?.value.duration;
    if (live != null && live > Duration.zero) return formatVideoClock(live);
    final seconds = widget.durationSeconds;
    if (seconds == null || seconds <= 0) return '';
    return formatVideoClock(Duration(seconds: seconds));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Product video (optional)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          const Text(
            'Show buyers a short clip of the item. Max 1 minute · up to 50 MB · MP4 / WebM / MOV / 3GP.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
          ),
          if (widget.checking) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Checking video size & length…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (_hasSource) _player() else _emptyPicker(),
          if (_hasSource) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusLabel(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                  label: const Text('Remove', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (widget.fileSizeBytes != null && widget.fileSizeBytes! > ProductVideoLimits.warnBytes) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Large file (${ProductVideoLimits.formatMb(widget.fileSizeBytes!)}). Keep under 50 MB or upload may fail.',
                  style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            OutlinedButton(
              onPressed: widget.checking ? null : widget.onPick,
              child: const Text('Replace video'),
            ),
          ],
          if ((widget.error ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(widget.error!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  String _statusLabel() {
    final parts = <String>[
      widget.filePath != null ? 'New video' : 'Current video',
    ];
    final duration = _durationLabel();
    if (duration.isNotEmpty) parts.add(duration);
    final bytes = widget.fileSizeBytes;
    if (bytes != null && bytes > 0) parts.add(ProductVideoLimits.formatMb(bytes));
    return parts.join(' · ');
  }

  Widget _emptyPicker() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: widget.checking ? null : widget.onPick,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDBA74), width: 1.6),
          ),
          child: const Column(
            children: [
              Icon(Icons.videocam_outlined, color: AppColors.accent, size: 36),
              SizedBox(height: 8),
              Text('Select product video', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Optional · max 1 minute · max 50 MB', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _player() {
    if (_failed) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final height = productVideoPreviewHeight(context, constraints.maxWidth);
          return Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off_outlined, color: Colors.white70),
                const SizedBox(height: 8),
                const Text('Could not load video', style: TextStyle(color: Colors.white70)),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          );
        },
      );
    }

    final controller = _controller;
    final ready = _ready && controller != null;
    final playing = ready && controller.value.isPlaying && !videoAtEnd(controller.value);
    final position = ready ? controller.value.position : Duration.zero;
    final duration = ready && controller.value.duration > Duration.zero
        ? controller.value.duration
        : Duration(seconds: widget.durationSeconds ?? 0);
    final ratio = ready && controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = productVideoPreviewHeight(context, constraints.maxWidth);
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!ready)
                    const Center(child: AppLoader())
                  else
                    Center(
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  if (ready)
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _togglePlay,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: playing ? 0 : 1,
                            child: Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF111827), size: 42),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 24, 4, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC111827), Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${formatVideoClock(position)} / ${formatVideoClock(duration)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: ready ? _toggleMute : null,
                            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
