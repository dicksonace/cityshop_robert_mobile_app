import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Plays CityShop ring assets for outgoing / incoming calls.
///
/// One looping player per ring: created once, stopped once. An earlier version
/// replayed short bursts, which meant building and tearing down a native player
/// — and requesting then abandoning audio focus — every couple of seconds for
/// the whole ring. That much native audio churn is enough to stall the platform
/// thread on low-end Android, which shows up as the app freezing.
///
/// The outgoing ringback also plays while WebRTC already owns the microphone, so
/// it declares the same voice-communication session instead of ringtone routing.
/// Two clients asking for different routes under a live recorder is what wedged
/// the audio HAL.
class CallRingtone {
  CallRingtone();

  static const _outgoingAsset = 'sounds/call_ringback.wav';
  static const _incomingAsset = 'sounds/call_ringtone.wav';

  /// Incoming: nothing else owns audio yet, so ring on the ringtone route.
  static final _incomingContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationRingtone,
      audioFocus: AndroidAudioFocus.gainTransient,
      audioMode: AndroidAudioMode.normal,
      isSpeakerphoneOn: false,
      stayAwake: false,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  /// Ringback: the mic is open by now, so join the session WebRTC set up rather
  /// than forcing a route change under it. No focus request either — WebRTC
  /// already holds focus, and asking again only churns it.
  static final _ringbackContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.voiceCommunication,
      audioFocus: AndroidAudioFocus.none,
      audioMode: AndroidAudioMode.inCommunication,
      isSpeakerphoneOn: false,
      stayAwake: false,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.mixWithOthers,
        AVAudioSessionOptions.allowBluetooth,
        AVAudioSessionOptions.defaultToSpeaker,
      },
    ),
  );

  AudioPlayer? _player;
  bool _active = false;
  String? _asset;
  AudioContext? _context;

  Future<void> startOutgoing() => _start(_outgoingAsset, _ringbackContext);

  Future<void> startIncoming() => _start(_incomingAsset, _incomingContext);

  Future<void> _start(String asset, AudioContext context) async {
    await stop();
    _active = true;
    _asset = asset;
    _context = context;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    await _play();
  }

  Future<void> _play() async {
    if (!_active || _asset == null || _player != null) return;
    final asset = _asset!;
    final context = _context!;
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setAudioContext(context);
      await player.setVolume(1.0);
      await player.play(AssetSource(asset));
    } catch (_) {
      // A teardown mid-setup lands here too; only beep if the ring is still
      // wanted, otherwise we'd chirp at someone who already hung up.
      final stillWanted = _active && identical(_player, player);
      if (identical(_player, player)) _player = null;
      await _dispose(player);
      if (stillWanted) {
        try {
          await SystemSound.play(SystemSoundType.alert);
        } catch (_) {}
      }
    }
  }

  Future<void> _teardown() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    await _dispose(player);
  }

  Future<void> _dispose(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> stop() async {
    _active = false;
    _asset = null;
    _context = null;
    await _teardown();
  }

  Future<void> dispose() => stop();
}
