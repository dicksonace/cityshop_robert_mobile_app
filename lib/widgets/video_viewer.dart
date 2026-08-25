import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../api/api_config.dart';
import '../services/media_cache.dart';
import '../theme/app_theme.dart';

/// Full-screen chat / media video player — tap play, scrub, close.
/// Downloads once, then plays from local cache (no data on replay).
Future<void> showVideoViewer(
  BuildContext context, {
  required String url,
}) {
  final resolved = ApiConfig.resolveMediaUrl(url);
  if (resolved.isEmpty) return Future.value();

  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VideoViewer(url: resolved),
    ),
  );
}

class VideoViewer extends StatefulWidget {
  const VideoViewer({super.key, required this.url});

  final String url;

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _showControls = true;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _open();
  }

  Future<void> _open() async {
    try {
      final file = await MediaCache.fileFor(widget.url);
      if (!mounted) return;
      final controller = VideoPlayerController.file(File(file.path));
      _controller = controller;
      controller.addListener(_onTick);
      await controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await controller.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _errorDetail = e.toString();
      });
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onTick);
    controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (!_ready || controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
    setState(() => _showControls = true);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final playing = _ready && controller != null && controller.value.isPlaying;
    final position = _ready && controller != null ? controller.value.position : Duration.zero;
    final duration = _ready && controller != null ? controller.value.duration : Duration.zero;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: Center(
                child: _failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 48),
                          const SizedBox(height: 12),
                          const Text('Could not play this video', style: TextStyle(color: Colors.white70)),
                          if ((_errorDetail ?? '').isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                _errorDetail!,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ),
                          ],
                        ],
                      )
                    : !_ready || controller == null
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.accent),
                              SizedBox(height: 12),
                              Text('Downloading for offline play…', style: TextStyle(color: Colors.white54)),
                            ],
                          )
                        : AspectRatio(
                            aspectRatio: controller.value.aspectRatio == 0
                                ? 16 / 9
                                : controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
              ),
            ),
            if (_showControls) ...[
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
              if (_ready && !_failed && controller != null)
                Center(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 56,
                      onPressed: _togglePlay,
                      icon: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (_ready && !_failed && controller != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: AppColors.accent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: (v) {
                            final target = Duration(
                              milliseconds: (duration.inMilliseconds * v).round(),
                            );
                            controller.seekTo(target);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Text(
                              _fmt(position),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const Spacer(),
                            Text(
                              _fmt(duration),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
