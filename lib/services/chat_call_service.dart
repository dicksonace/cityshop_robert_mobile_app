import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import 'call_ringtone.dart';

enum ChatCallState { idle, calling, incoming, active }

enum ChatCallKind { voice, video }

enum ChatCallEndReason { declined, completed, missed, cancelled }

/// In-app WebRTC voice/video calls over the chat signal API.
///
/// Important: do NOT touch native WebRTC (renderers / getUserMedia / PC) on
/// `call_offer`. That path ran on every polled/realtime offer and wedged the
/// Android camera/audio HAL so the app froze until a phone reboot.
class ChatCallService extends ChangeNotifier {
  ChatCallService({
    required this.store,
    required this.conversationId,
    required this.myUserId,
    required this.myName,
    this.onCallLog,
  });

  final AppStore store;
  final int conversationId;
  final int myUserId;
  final String myName;
  final void Function(ChatMessage message)? onCallLog;

  static const _offerTtl = Duration(seconds: 60);

  ChatCallState state = ChatCallState.idle;
  ChatCallKind kind = ChatCallKind.voice;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCSessionDescription? _pendingOffer;
  DateTime? _pendingOfferAt;
  final Set<int> _processedIds = {};
  final ListQueue<RTCIceCandidate> _pendingRemoteIce = ListQueue();
  final ListQueue<ChatMessage> _signalQueue = ListQueue();
  bool _drainingSignals = false;
  int? _callerId;
  String _callerName = '';
  String peerName = '';
  DateTime? _startedAt;
  bool _renderersReady = false;
  bool _disposed = false;
  final _ringtone = CallRingtone();

  bool get renderersReady => _renderersReady;

  Future<void> initRenderers() async {
    if (_disposed || _renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> disposeService() async {
    if (_disposed) return;
    _disposed = true;
    _signalQueue.clear();
    await _cleanup(disposeRenderers: true);
    await _ringtone.dispose();
  }

  Future<Map<String, dynamic>?> _sendSignal(
    String type, {
    String body = '',
    Map<String, dynamic>? metadata,
  }) {
    return store.sendCallSignal(
      conversationId,
      type,
      body: body,
      metadata: {
        'call_kind': kind == ChatCallKind.video ? 'video' : 'voice',
        ...?metadata,
      },
    );
  }

  Future<void> _stopTracks(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> _cleanup({bool disposeRenderers = false}) async {
    await _ringtone.stop();
    _pendingRemoteIce.clear();
    _pendingOffer = null;
    _pendingOfferAt = null;
    _startedAt = null;

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }

    final local = _localStream;
    _localStream = null;
    await _stopTracks(local);

    try {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    } catch (_) {}

    if (disposeRenderers && _renderersReady) {
      try {
        await localRenderer.dispose();
      } catch (_) {}
      try {
        await remoteRenderer.dispose();
      } catch (_) {}
      _renderersReady = false;
    }

    kind = ChatCallKind.voice;
    if (state != ChatCallState.idle) {
      state = ChatCallState.idle;
      notifyListeners();
    } else {
      state = ChatCallState.idle;
    }
  }

  Future<bool> _ensurePermissions(ChatCallKind callKind) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (callKind == ChatCallKind.video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  Future<RTCPeerConnection> _createPeer() async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    pc.onTrack = (event) {
      if (_disposed || event.streams.isEmpty) return;
      remoteRenderer.srcObject = event.streams.first;
      notifyListeners();
    };
    pc.onIceCandidate = (candidate) {
      if (_disposed) return;
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      unawaited(
        _sendSignal(
          'call_ice',
          metadata: {
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          },
        ),
      );
    };
    return pc;
  }

  Future<void> _flushPendingIce() async {
    final pc = _pc;
    if (pc == null) return;
    while (_pendingRemoteIce.isNotEmpty) {
      final c = _pendingRemoteIce.removeFirst();
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> startCall(ChatCallKind callKind) async {
    if (_disposed || state != ChatCallState.idle) return;
    await initRenderers();
    if (!await _ensurePermissions(callKind)) {
      throw StateError(
        callKind == ChatCallKind.video
            ? 'Camera and microphone permission required'
            : 'Microphone permission required',
      );
    }

    _callerId = myUserId;
    _callerName = myName;
    kind = callKind;

    try {
      await _ringtone.stop();
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': callKind == ChatCallKind.video,
      });
      localRenderer.srcObject = _localStream;
      _pc = await _createPeer();
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _sendSignal(
        'call_offer',
        body: callKind == ChatCallKind.video ? 'Video call' : 'Voice call',
        metadata: {
          'sdp': {'type': offer.type, 'sdp': offer.sdp},
        },
      );
      state = ChatCallState.calling;
      notifyListeners();
      unawaited(_ringtone.startOutgoing());
    } catch (e) {
      await _cleanup();
      rethrow;
    }
  }

  Future<void> acceptCall() async {
    if (_disposed) return;
    final offer = _pendingOffer;
    if (offer == null) return;
    if (_pendingOfferAt != null &&
        DateTime.now().difference(_pendingOfferAt!) > _offerTtl) {
      await _cleanup();
      throw StateError('That call has expired. Ask them to call again.');
    }

    await initRenderers();
    if (!await _ensurePermissions(kind)) {
      throw StateError('Microphone/camera permission required');
    }

    try {
      await _ringtone.stop();
      // Brief pause so audioplayers releases the audio focus before WebRTC.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': kind == ChatCallKind.video,
      });
      localRenderer.srcObject = _localStream;
      _pc = await _createPeer();
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      await _pc!.setRemoteDescription(offer);
      await _flushPendingIce();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _sendSignal(
        'call_answer',
        metadata: {
          'sdp': {'type': answer.type, 'sdp': answer.sdp},
        },
      );
      _pendingOffer = null;
      _pendingOfferAt = null;
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    } catch (e) {
      await _cleanup();
      rethrow;
    }
  }

  Future<void> endCall([ChatCallEndReason? reason]) async {
    if (_disposed || state == ChatCallState.idle) return;

    final status = reason != null
        ? reason.name
        : state == ChatCallState.active
            ? 'completed'
            : state == ChatCallState.incoming
                ? 'declined'
                : 'cancelled';

    final duration = state == ChatCallState.active && _startedAt != null
        ? DateTime.now().difference(_startedAt!).inSeconds.clamp(0, 86400)
        : 0;

    try {
      final result = await _sendSignal(
        'call_end',
        metadata: {
          'call_log': {
            'status': status,
            'caller_id': _callerId ?? myUserId,
            'caller_name': _callerName.isEmpty ? myName : _callerName,
            'duration_seconds': duration,
            'call_kind': kind == ChatCallKind.video ? 'video' : 'voice',
          },
        },
      );
      final log = result?['call_log'];
      if (log is Map && onCallLog != null) {
        onCallLog!(
          ChatMessage.fromJson(Map<String, dynamic>.from(log), myUserId: myUserId),
        );
      }
    } catch (_) {
      // Hang-up should always tear down locally.
    }
    await _cleanup();
  }

  /// Queue signalling so poll/realtime storms cannot interleave mid-setup.
  Future<void> handleMessage(ChatMessage msg) async {
    if (_disposed) return;
    if (!msg.type.startsWith('call') || msg.type == 'call_log') return;
    if (_processedIds.contains(msg.id)) return;
    _processedIds.add(msg.id);
    if (_processedIds.length > 400) {
      _processedIds.clear();
    }

    _signalQueue.add(msg);
    if (_drainingSignals) return;
    _drainingSignals = true;
    try {
      while (!_disposed && _signalQueue.isNotEmpty) {
        final next = _signalQueue.removeFirst();
        await _handleSignal(next);
      }
    } finally {
      _drainingSignals = false;
    }
  }

  bool _isStale(ChatMessage msg) {
    final raw = msg.createdAt;
    if (raw == null || raw.isEmpty) return false;
    final at = DateTime.tryParse(raw);
    if (at == null) return false;
    return DateTime.now().difference(at.toLocal()) > _offerTtl;
  }

  Future<void> _handleSignal(ChatMessage msg) async {
    if (_disposed) return;

    if (msg.type == 'call_end') {
      await _cleanup();
      return;
    }

    final meta = msg.metadata ?? {};

    // Another device of ours answered — drop the ringing UI without touching WebRTC.
    if (msg.type == 'call_answer' && msg.senderId == myUserId) {
      if (state == ChatCallState.incoming || state == ChatCallState.calling) {
        await _ringtone.stop();
        await _cleanup();
      }
      return;
    }

    if (msg.type == 'call_offer' && msg.senderId != null && msg.senderId != myUserId) {
      if (_isStale(msg)) return;
      // Already in a live call — ignore a second offer.
      if (state == ChatCallState.active || state == ChatCallState.calling) return;

      // Soft reset previous ringing UI only (no native WebRTC yet).
      await _ringtone.stop();
      kind = meta['call_kind'] == 'video' ? ChatCallKind.video : ChatCallKind.voice;
      _callerId = msg.senderId;
      _callerName = peerName.isNotEmpty ? peerName : 'Caller';
      final sdp = meta['sdp'];
      if (sdp is Map) {
        _pendingOffer = RTCSessionDescription(
          sdp['sdp'] as String?,
          sdp['type'] as String?,
        );
        _pendingOfferAt = DateTime.tryParse(msg.createdAt ?? '')?.toLocal() ?? DateTime.now();
      } else {
        return;
      }
      _pendingRemoteIce.clear();
      state = ChatCallState.incoming;
      notifyListeners();
      unawaited(_ringtone.startIncoming());
      return;
    }

    if (msg.type == 'call_ice' && meta['candidate'] is Map) {
      final c = Map<String, dynamic>.from(meta['candidate'] as Map);
      final ice = RTCIceCandidate(
        c['candidate'] as String?,
        c['sdpMid'] as String?,
        (c['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (_pc == null) {
        // Buffer candidates that arrive while still ringing / before setRemoteDescription.
        if (state == ChatCallState.incoming || state == ChatCallState.calling) {
          _pendingRemoteIce.add(ice);
          if (_pendingRemoteIce.length > 80) {
            _pendingRemoteIce.removeFirst();
          }
        }
        return;
      }
      try {
        await _pc!.addCandidate(ice);
      } catch (_) {}
      return;
    }

    if (_pc == null) return;

    if (msg.type == 'call_answer' && meta['sdp'] is Map) {
      await _ringtone.stop();
      final sdp = Map<String, dynamic>.from(meta['sdp'] as Map);
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?),
      );
      await _flushPendingIce();
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    }
  }
}
