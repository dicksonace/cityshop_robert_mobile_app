import 'dart:async';

import 'package:flutter/services.dart';

/// Incoming/outgoing ring without holding a looping AudioPlayer.
///
/// Looping `audioplayers` + WebRTC `getUserMedia` was wedging Android's audio
/// HAL so the app froze until a phone reboot (including stuck on splash).
class CallRingtone {
  CallRingtone();

  Timer? _timer;
  bool _active = false;

  Future<void> startOutgoing() => _start(heavy: false);

  Future<void> startIncoming() => _start(heavy: true);

  Future<void> _start({required bool heavy}) async {
    await stop();
    _active = true;
    if (heavy) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) async {
      if (!_active) return;
      if (heavy) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() => stop();
}
