import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class MediaSendDraft {
  const MediaSendDraft({required this.caption, required this.viewOnce});

  final String caption;
  final bool viewOnce;
}

/// WhatsApp-style caption bar with a circled “1” for view once.
class MediaCaptionScreen extends StatefulWidget {
  const MediaCaptionScreen({
    super.key,
    required this.path,
    required this.isVideo,
    this.initialCaption = '',
  });

  final String path;
  final bool isVideo;
  final String initialCaption;

  @override
  State<MediaCaptionScreen> createState() => _MediaCaptionScreenState();
}

class _MediaCaptionScreenState extends State<MediaCaptionScreen> {
  late final TextEditingController _caption;
  bool viewOnce = false;

  @override
  void initState() {
    super.initState();
    _caption = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _send() {
    Navigator.pop(
      context,
      MediaSendDraft(caption: _caption.text.trim(), viewOnce: viewOnce),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.isVideo ? 'Video' : 'Photo'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.isVideo
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_rounded, color: Colors.white70, size: 72),
                        SizedBox(height: 12),
                        Text('Video selected', style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : Image.file(File(widget.path), fit: BoxFit.contain),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Tooltip(
                    message: viewOnce ? 'View once on' : 'View once',
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
                        child: Text(
                          '1',
                          style: TextStyle(
                            color: viewOnce ? Colors.white : Colors.white,
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
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
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
                    onPressed: _send,
                    style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
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
