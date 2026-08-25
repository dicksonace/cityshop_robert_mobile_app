import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Burns a transparent PNG overlay onto every frame of [videoPath].
class VideoOverlay {
  VideoOverlay._();

  static Future<String> burnOverlay({
    required String videoPath,
    required String overlayPngPath,
  }) async {
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/chat_vid_overlay_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      videoPath,
      '-i',
      overlayPngPath,
      '-filter_complex',
      '[1:v][0:v]scale2ref[ov][base];[base][ov]overlay=0:0',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      out.path,
    ]);

    final code = await session.getReturnCode();
    if (ReturnCode.isSuccess(code) && await out.exists() && await out.length() > 0) {
      return out.path;
    }

    final session2 = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      videoPath,
      '-i',
      overlayPngPath,
      '-filter_complex',
      'overlay=0:0',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      out.path,
    ]);
    final code2 = await session2.getReturnCode();
    if (!ReturnCode.isSuccess(code2) || !await out.exists()) {
      throw StateError('Could not apply text/drawing to this video.');
    }
    return out.path;
  }
}
