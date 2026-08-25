import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../../theme/app_theme.dart';

/// WhatsApp-style video trim: filmstrip + start/end handles. Pops trimmed file path.
class VideoTrimScreen extends StatefulWidget {
  const VideoTrimScreen({super.key, required this.path});

  final String path;

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final Trimmer _trimmer = Trimmer();
  double _start = 0;
  double _end = 0;
  bool _playing = false;
  bool _saving = false;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _trimmer.loadVideo(videoFile: File(widget.path));
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open this video for trimming.');
    }
  }

  Future<void> _save() async {
    if (_saving || !_ready) return;
    setState(() => _saving = true);
    try {
      String? outPath;
      await _trimmer.saveTrimmedVideo(
        startValue: _start,
        endValue: _end,
        videoFileName: 'chat_trim_${DateTime.now().millisecondsSinceEpoch}',
        onSave: (path) => outPath = path,
      );
      if (!mounted) return;
      if (outPath == null || outPath!.isEmpty) {
        throw StateError('Trim failed');
      }
      Navigator.pop(context, outPath);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not trim this video')),
        );
        setState(() => _saving = false);
      }
    }
  }

  String _fmt(double ms) {
    final total = (ms / 1000).round().clamp(0, 99999);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Trim video'),
        actions: [
          TextButton(
            onPressed: _saving || !_ready ? null : _save,
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
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
          : !_ready
              ? const Center(child: CircularProgressIndicator(color: Colors.white54))
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: VideoViewer(trimmer: _trimmer),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () async {
                              final playing = await _trimmer.videoPlaybackControl(
                                startValue: _start,
                                endValue: _end,
                              );
                              if (mounted) setState(() => _playing = playing);
                            },
                            icon: Icon(
                              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                          Text(
                            '${_fmt(_start)} – ${_fmt(_end)}',
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        child: TrimViewer(
                          trimmer: _trimmer,
                          viewerHeight: 56,
                          viewerWidth: MediaQuery.sizeOf(context).width - 16,
                          maxVideoLength: const Duration(minutes: 5),
                          editorProperties: TrimEditorProperties(
                            borderPaintColor: AppColors.accent,
                            circlePaintColor: Colors.white,
                            scrubberPaintColor: AppColors.accent,
                          ),
                          areaProperties: TrimAreaProperties.edgeBlur(
                            thumbnailQuality: 20,
                          ),
                          onChangeStart: (v) => _start = v,
                          onChangeEnd: (v) => _end = v,
                          onChangePlaybackState: (playing) {
                            if (mounted) setState(() => _playing = playing);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
