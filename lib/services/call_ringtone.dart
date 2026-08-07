import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Loops ringback / ringtone assets during call setup.
class CallRingtone {
  CallRingtone();

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  Future<void> startOutgoing() => _start('assets/sounds/call_ringback.wav', volume: 0.55);

  Future<void> startIncoming() async {
    HapticFeedback.heavyImpact();
    await _start('assets/sounds/call_ringtone.wav', volume: 0.85);
  }

  Future<void> _start(String asset, {required double volume}) async {
    await stop();
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(volume);
      await _player.play(AssetSource(asset.replaceFirst('assets/', '')));
      _playing = true;
    } catch (_) {
      // Missing asset / platform audio issue — silent fail.
      _playing = false;
    }
  }

  Future<void> stop() async {
    if (!_playing) {
      try {
        await _player.stop();
      } catch (_) {}
      return;
    }
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
