import 'package:video_player/video_player.dart';

/// True when the clip has finished or is within the last ~300 ms.
bool videoAtEnd(VideoPlayerValue value) {
  if (!value.isInitialized) return false;
  if (value.isCompleted) return true;
  final totalMs = value.duration.inMilliseconds;
  if (totalMs <= 0) return false;
  return value.position.inMilliseconds >= totalMs - 300;
}

/// Tap play/pause — always restarts from the beginning when the clip ended.
Future<void> toggleVideoPlayback(VideoPlayerController controller) async {
  final value = controller.value;
  if (value.isPlaying && !videoAtEnd(value)) {
    await controller.pause();
    return;
  }
  if (videoAtEnd(value)) {
    await controller.seekTo(Duration.zero);
  }
  await controller.play();
}
