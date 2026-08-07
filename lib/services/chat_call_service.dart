import 'dart:async';

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

  ChatCallState state = ChatCallState.idle;
  ChatCallKind kind = ChatCallKind.voice;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCSessionDescription? _pendingOffer;
  final Set<int> _processedIds = {};
  int? _callerId;
  String _callerName = '';
  String peerName = '';
  DateTime? _startedAt;
  bool _renderersReady = false;
  final _ringtone = CallRingtone();

  Future<void> init() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> disposeService() async {
    await _cleanup();
    await _ringtone.dispose();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
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

  Future<void> _cleanup() async {
    await _ringtone.stop();
    await _pc?.close();
    _pc = null;
    await _localStream?.dispose();
    _localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _pendingOffer = null;
    _startedAt = null;
    kind = ChatCallKind.voice;
    state = ChatCallState.idle;
    notifyListeners();
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
      if (event.streams.isEmpty) return;
      remoteRenderer.srcObject = event.streams.first;
      notifyListeners();
    };
    pc.onIceCandidate = (candidate) {
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

  Future<void> startCall(ChatCallKind callKind) async {
    if (state != ChatCallState.idle) return;
    await init();
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
    final offer = _pendingOffer;
    if (offer == null) return;
    await init();
    if (!await _ensurePermissions(kind)) {
      throw StateError('Microphone/camera permission required');
    }

    try {
      await _ringtone.stop();
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
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _sendSignal(
        'call_answer',
        metadata: {
          'sdp': {'type': answer.type, 'sdp': answer.sdp},
        },
      );
      _pendingOffer = null;
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    } catch (e) {
      await _cleanup();
      rethrow;
    }
  }

  Future<void> endCall([ChatCallEndReason? reason]) async {
    if (state == ChatCallState.idle) return;

    final status = reason != null
        ? reason.name
        : state == ChatCallState.active
            ? 'completed'
            : state == ChatCallState.incoming
                ? 'declined'
                : state == ChatCallState.calling
                    ? 'missed'
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

  Future<void> handleMessage(ChatMessage msg) async {
    if (!msg.type.startsWith('call') || msg.type == 'call_log') return;
    if (_processedIds.contains(msg.id)) return;
    _processedIds.add(msg.id);

    if (msg.type == 'call_end') {
      await _cleanup();
      return;
    }

    final meta = msg.metadata ?? {};

    if (msg.type == 'call_offer' && msg.senderId != null && msg.senderId != myUserId) {
      await init();
      kind = meta['call_kind'] == 'video' ? ChatCallKind.video : ChatCallKind.voice;
      _callerId = msg.senderId;
      _callerName = peerName.isNotEmpty ? peerName : 'Caller';
      final sdp = meta['sdp'];
      if (sdp is Map) {
        _pendingOffer = RTCSessionDescription(
          sdp['sdp'] as String?,
          sdp['type'] as String?,
        );
      }
      state = ChatCallState.incoming;
      notifyListeners();
      unawaited(_ringtone.startIncoming());
      return;
    }

    if (_pc == null) return;

    if (msg.type == 'call_answer' && meta['sdp'] is Map) {
      await _ringtone.stop();
      final sdp = Map<String, dynamic>.from(meta['sdp'] as Map);
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?),
      );
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    }

    if (msg.type == 'call_ice' && meta['candidate'] is Map) {
      final c = Map<String, dynamic>.from(meta['candidate'] as Map);
      try {
        await _pc!.addCandidate(
          RTCIceCandidate(
            c['candidate'] as String?,
            c['sdpMid'] as String?,
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ),
        );
      } catch (_) {}
    }
  }
}
