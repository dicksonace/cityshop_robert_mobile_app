import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One-shot cash ding when money lands in the wallet (QR / chat transfer).
class MoneySound {
  MoneySound._();

  static AudioPlayer? _player;
  static DateTime? _lastPlayedAt;

  static const _asset = 'sounds/money_received.wav';

  static Future<void> playReceived() async {
    final now = DateTime.now();
    final last = _lastPlayedAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 1400)) {
      return;
    }
    _lastPlayedAt = now;

    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(0.9);
      await player.play(AssetSource(_asset));
    } catch (e) {
      debugPrint('CityShop money sound failed: $e');
    }
  }
}
