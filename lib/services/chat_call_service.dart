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

  /// How long the callee may take to tap Accept after the offer is received.
  static const _ringTtl = Duration(seconds: 120);

  /// Drop poll-replayed offers older than this (dead calls).
  static const _offerMaxAge = Duration(minutes: 3);

  ChatCallState state = ChatCallState.idle;
  ChatCallKind kind = ChatCallKind.voice;

  /// Video-only. Never create/init these for voice — Android camera surfaces
  /// from RTCVideoRenderer were wedging the HAL and freezing the whole app.
  RTCVideoRenderer? localRenderer;
  RTCVideoRenderer? remoteRenderer;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCSessionDescription? _pendingOffer;
  DateTime? _pendingOfferReceivedAt;
  final Set<int> _processedIds = {};
  final ListQueue<RTCIceCandidate> _pendingRemoteIce = ListQueue();
  final ListQueue<ChatMessage> _signalQueue = ListQueue();
  bool _drainingSignals = false;
  Future<void> _opChain = Future<void>.value();
  int? _callerId;
  String _callerName = '';
  String peerName = '';
  DateTime? _startedAt;
  bool _renderersReady = false;
  bool _disposed = false;
  bool _accepting = false;
  bool _remoteHangup = false;
  final _ringtone = CallRingtone();

  bool get renderersReady => _renderersReady;

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _opChain = _opChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _ensureVideoRenderers() async {
    if (_disposed || _renderersReady) return;
    localRenderer ??= RTCVideoRenderer();
    remoteRenderer ??= RTCVideoRenderer();
    await localRenderer!.initialize();
    await remoteRenderer!.initialize();
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
    _pendingOfferReceivedAt = null;
    _startedAt = null;
    _accepting = false;
    _remoteHangup = false;

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
      localRenderer?.srcObject = null;
      remoteRenderer?.srcObject = null;
    } catch (_) {}

    // Always release video surfaces after a call — keeping them alive wedges Android.
    if (_renderersReady || localRenderer != null || remoteRenderer != null) {
      try {
        await localRenderer?.dispose();
      } catch (_) {}
      try {
        await remoteRenderer?.dispose();
      } catch (_) {}
      localRenderer = null;
      remoteRenderer = null;
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

  Future<MediaStream> _openLocalMedia(ChatCallKind callKind) {
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': callKind == ChatCallKind.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
            }
          : false,
    });
  }

  Future<RTCPeerConnection> _createPeer() async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });
    pc.onTrack = (event) {
      if (_disposed || event.streams.isEmpty) return;
      if (_renderersReady) {
        remoteRenderer?.srcObject = event.streams.first;
      }
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

  Map<String, dynamic>? _asStringKeyedMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  RTCSessionDescription? _sdpFromMeta(dynamic raw) {
    final sdp = _asStringKeyedMap(raw);
    if (sdp == null) return null;
    final description = sdp['sdp']?.toString();
    final type = sdp['type']?.toString();
    if (description == null || description.isEmpty || type == null || type.isEmpty) {
      return null;
    }
    return RTCSessionDescription(description, type);
  }

  Future<void> startCall(ChatCallKind callKind) {
    return _runExclusive(() async {
      if (_disposed || state != ChatCallState.idle) return;
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

      // Paint the calling UI before touching native WebRTC so a hung mic
      // doesn't look like a dead tap — and so we can hang up / recover.
      state = ChatCallState.calling;
      notifyListeners();
      unawaited(_ringtone.startOutgoing());
      await Future<void>.delayed(const Duration(milliseconds: 80));

      try {
        if (callKind == ChatCallKind.video) {
          await _ensureVideoRenderers().timeout(const Duration(seconds: 8));
        }
        _localStream = await _openLocalMedia(callKind).timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            throw StateError(
              'Microphone is busy or not responding. Close other apps and try again.',
            );
          },
        );
        if (_disposed || state != ChatCallState.calling) {
          await _stopTracks(_localStream);
          _localStream = null;
          return;
        }
        if (callKind == ChatCallKind.video) {
          localRenderer?.srcObject = _localStream;
        }
        _pc = await _createPeer().timeout(const Duration(seconds: 8));
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
      } catch (e) {
        await _cleanup();
        if (e is StateError) rethrow;
        if (e is TimeoutException) {
          throw StateError(
            'Could not start call — microphone timed out. Try again.',
          );
        }
        rethrow;
      }
    });
  }

  Future<void> acceptCall() {
    return _runExclusive(() async {
      if (_disposed) return;
      final offer = _pendingOffer;
      if (offer == null) {
        throw StateError('That call is no longer available. Ask them to call again.');
      }
      if (_pendingOfferReceivedAt != null &&
          DateTime.now().difference(_pendingOfferReceivedAt!) > _ringTtl) {
        await _cleanup();
        throw StateError('That call has expired. Ask them to call again.');
      }

      _accepting = true;
      _remoteHangup = false;
      if (!await _ensurePermissions(kind)) {
        _accepting = false;
        throw StateError(
          kind == ChatCallKind.video
              ? 'Camera and microphone permission required'
              : 'Microphone permission required',
        );
      }

      try {
        await _ringtone.stop();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (_disposed || _remoteHangup || _pendingOffer == null) {
          throw StateError('Caller hung up before you could join.');
        }

        if (kind == ChatCallKind.video) {
          await _ensureVideoRenderers();
        }
        _localStream = await _openLocalMedia(kind);
        if (_disposed || _remoteHangup || _pendingOffer == null) {
          await _stopTracks(_localStream);
          _localStream = null;
          throw StateError('Caller hung up before you could join.');
        }

        if (kind == ChatCallKind.video) {
          localRenderer?.srcObject = _localStream;
        }
        _pc = await _createPeer();
        for (final track in _localStream!.getTracks()) {
          await _pc!.addTrack(track, _localStream!);
        }
        await _pc!.setRemoteDescription(offer);
        await _flushPendingIce();
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        if (_remoteHangup) {
          throw StateError('Caller hung up before you could join.');
        }
        await _sendSignal(
          'call_answer',
          metadata: {
            'sdp': {'type': answer.type, 'sdp': answer.sdp},
          },
        );
        _pendingOffer = null;
        _pendingOfferReceivedAt = null;
        _startedAt = DateTime.now();
        _accepting = false;
        state = ChatCallState.active;
        notifyListeners();
      } catch (e) {
        _accepting = false;
        await _cleanup();
        if (e is StateError) rethrow;
        throw StateError(_friendlyJoinError(e));
      }
    });
  }

  String _friendlyJoinError(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('permission') || text.contains('notallowed') || text.contains('denied')) {
      return kind == ChatCallKind.video
          ? 'Camera/microphone permission required'
          : 'Microphone permission required';
    }
    if (text.contains('getusermedia') || text.contains('notreadable') || text.contains('track')) {
      return 'Could not access microphone/camera. Close other apps using them and try again.';
    }
    if (text.contains('sdp') || text.contains('description') || text.contains('setremote')) {
      return 'Call signal was invalid. Ask them to call again.';
    }
    return 'Could not join call. Ask them to call again.';
  }

  Future<void> endCall([ChatCallEndReason? reason]) {
    return _runExclusive(() async {
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
    });
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

    // Hang-ups must interrupt Accept immediately (don't sit behind the op lock).
    if (msg.type == 'call_end') {
      _remoteHangup = true;
      _pendingOffer = null;
      _pendingOfferReceivedAt = null;
      if (_accepting) return;
      await _runExclusive(() async {
        if (!_disposed) await _cleanup();
      });
      return;
    }

    _signalQueue.add(msg);
    if (_drainingSignals) return;
    _drainingSignals = true;
    try {
      while (!_disposed && _signalQueue.isNotEmpty) {
        final next = _signalQueue.removeFirst();
        await _runExclusive(() => _handleSignal(next));
      }
    } finally {
      _drainingSignals = false;
    }
  }

  bool _isAncientOffer(ChatMessage msg) {
    final raw = msg.createdAt;
    if (raw == null || raw.isEmpty) return false;
    final at = DateTime.tryParse(raw);
    if (at == null) return false;
    return DateTime.now().difference(at.toLocal()) > _offerMaxAge;
  }

  Future<void> _handleSignal(ChatMessage msg) async {
    if (_disposed) return;

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
      if (_isAncientOffer(msg)) return;
      // Already in a live call — ignore a second offer.
      if (state == ChatCallState.active || state == ChatCallState.calling || _accepting) {
        return;
      }

      final offer = _sdpFromMeta(meta['sdp']);
      if (offer == null) return;

      // Soft reset previous ringing UI only (no native WebRTC yet).
      await _ringtone.stop();
      kind = meta['call_kind'] == 'video' ? ChatCallKind.video : ChatCallKind.voice;
      _callerId = msg.senderId;
      _callerName = peerName.isNotEmpty ? peerName : 'Caller';
      _pendingOffer = offer;
      // TTL starts when *we* receive the offer, not when it was created on the server.
      _pendingOfferReceivedAt = DateTime.now();
      _remoteHangup = false;
      _pendingRemoteIce.clear();
      state = ChatCallState.incoming;
      notifyListeners();
      unawaited(_ringtone.startIncoming());
      return;
    }

    if (msg.type == 'call_ice') {
      final c = _asStringKeyedMap(meta['candidate']);
      if (c == null) return;
      final ice = RTCIceCandidate(
        c['candidate']?.toString(),
        c['sdpMid']?.toString(),
        (c['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (_pc == null) {
        // Buffer candidates that arrive while still ringing / before setRemoteDescription.
        if (state == ChatCallState.incoming || state == ChatCallState.calling || _accepting) {
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

    if (msg.type == 'call_answer') {
      final answer = _sdpFromMeta(meta['sdp']);
      if (answer == null) return;
      await _ringtone.stop();
      await _pc!.setRemoteDescription(answer);
      await _flushPendingIce();
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    }
  }
}
