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
/// Hang up must NEVER wait on `getUserMedia` / peer-setup. Those native calls
/// can block ~2 minutes on Android; if Hang up sat behind them the UI stayed
/// on "Calling…" until they finished. We use a session generation so in-flight
/// media is discarded the moment the user hangs up.
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

  static const _ringTtl = Duration(seconds: 120);
  static const _offerMaxAge = Duration(minutes: 3);
  static const _mediaTimeout = Duration(seconds: 6);

  ChatCallState state = ChatCallState.idle;
  ChatCallKind kind = ChatCallKind.voice;

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
  int? _callerId;
  String _callerName = '';
  String peerName = '';
  DateTime? _startedAt;
  bool _renderersReady = false;
  bool _disposed = false;

  /// Bumped on hang-up / cleanup so in-flight start/accept aborts.
  int _session = 0;

  final _ringtone = CallRingtone();

  bool get renderersReady => _renderersReady;

  bool _alive(int session) => !_disposed && session == _session;

  Future<void> disposeService() async {
    if (_disposed) return;
    _disposed = true;
    _session++;
    _signalQueue.clear();
    await _ringtone.stop();
    await _tearDownMedia();
    state = ChatCallState.idle;
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

  Future<void> _tearDownMedia() async {
    _pendingRemoteIce.clear();
    _pendingOffer = null;
    _pendingOfferReceivedAt = null;
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
      localRenderer?.srcObject = null;
      remoteRenderer?.srcObject = null;
    } catch (_) {}

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
  }

  Future<void> _dismissUi() async {
    await _ringtone.stop();
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
    }).timeout(
      _mediaTimeout,
      onTimeout: () {
        throw StateError(
          'Microphone timed out. Close other apps using the mic, then try again.',
        );
      },
    );
  }

  Future<void> _ensureVideoRenderers(int session) async {
    if (!_alive(session) || _renderersReady) return;
    localRenderer ??= RTCVideoRenderer();
    remoteRenderer ??= RTCVideoRenderer();
    await localRenderer!.initialize().timeout(_mediaTimeout);
    if (!_alive(session)) return;
    await remoteRenderer!.initialize().timeout(_mediaTimeout);
    if (_alive(session)) _renderersReady = true;
  }

  Future<RTCPeerConnection> _createPeer(int session) async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    }).timeout(_mediaTimeout);
    pc.onTrack = (event) {
      if (!_alive(session) || event.streams.isEmpty) return;
      if (_renderersReady) {
        remoteRenderer?.srcObject = event.streams.first;
      }
      notifyListeners();
    };
    pc.onIceCandidate = (candidate) {
      if (!_alive(session)) return;
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

  Future<void> startCall(ChatCallKind callKind) async {
    if (_disposed || state != ChatCallState.idle) return;
    if (!await _ensurePermissions(callKind)) {
      throw StateError(
        callKind == ChatCallKind.video
            ? 'Camera and microphone permission required'
            : 'Microphone permission required',
      );
    }
    if (_disposed || state != ChatCallState.idle) return;

    final session = _session;
    _callerId = myUserId;
    _callerName = myName;
    kind = callKind;

    // Show "Calling…" immediately — Hang up can dismiss without waiting on mic.
    state = ChatCallState.calling;
    notifyListeners();
    unawaited(_ringtone.startOutgoing());

    try {
      if (callKind == ChatCallKind.video) {
        await _ensureVideoRenderers(session);
        if (!_alive(session) || state != ChatCallState.calling) return;
      }

      final stream = await _openLocalMedia(callKind);
      if (!_alive(session) || state != ChatCallState.calling) {
        await _stopTracks(stream);
        return;
      }
      _localStream = stream;
      if (callKind == ChatCallKind.video) {
        localRenderer?.srcObject = _localStream;
      }

      final pc = await _createPeer(session);
      if (!_alive(session) || state != ChatCallState.calling) {
        try {
          await pc.close();
          await pc.dispose();
        } catch (_) {}
        return;
      }
      _pc = pc;
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      if (!_alive(session) || state != ChatCallState.calling) return;

      await _sendSignal(
        'call_offer',
        body: callKind == ChatCallKind.video ? 'Video call' : 'Voice call',
        metadata: {
          'sdp': {'type': offer.type, 'sdp': offer.sdp},
        },
      );
    } catch (e) {
      if (!_alive(session)) return;
      await _tearDownMedia();
      await _dismissUi();
      if (e is StateError) rethrow;
      throw StateError(_friendlyStartError(e));
    }
  }

  String _friendlyStartError(Object e) {
    final text = e.toString().toLowerCase();
    if (e is TimeoutException || text.contains('timeout')) {
      return 'Microphone timed out. Close other apps using the mic, then try again.';
    }
    if (text.contains('permission') || text.contains('notallowed') || text.contains('denied')) {
      return kind == ChatCallKind.video
          ? 'Allow camera and microphone in phone Settings, then try again.'
          : 'Allow microphone in phone Settings, then try again.';
    }
    if (text.contains('getusermedia') ||
        text.contains('notreadable') ||
        text.contains('track') ||
        text.contains('device') ||
        text.contains('busy') ||
        text.contains('in use')) {
      return 'Microphone is busy. Close WhatsApp/other apps using the mic, or reboot the phone, then try again.';
    }
    if (text.contains('peerconnection') || text.contains('webrtc')) {
      return 'Call engine failed to start. Force-close CityShop and open it again.';
    }
    return 'Could not start call. Check mic permission, or reboot the phone if a call froze earlier.';
  }

  Future<void> acceptCall() async {
    if (_disposed) return;
    final offer = _pendingOffer;
    if (offer == null) {
      throw StateError('That call is no longer available. Ask them to call again.');
    }
    if (_pendingOfferReceivedAt != null &&
        DateTime.now().difference(_pendingOfferReceivedAt!) > _ringTtl) {
      _session++;
      await _tearDownMedia();
      await _dismissUi();
      throw StateError('That call has expired. Ask them to call again.');
    }

    final session = _session;
    if (!await _ensurePermissions(kind)) {
      throw StateError(
        kind == ChatCallKind.video
            ? 'Camera and microphone permission required'
            : 'Microphone permission required',
      );
    }
    if (!_alive(session) || _pendingOffer == null) {
      throw StateError('Caller hung up before you could join.');
    }

    try {
      await _ringtone.stop();
      if (!_alive(session) || _pendingOffer == null) {
        throw StateError('Caller hung up before you could join.');
      }

      if (kind == ChatCallKind.video) {
        await _ensureVideoRenderers(session);
        if (!_alive(session)) {
          throw StateError('Caller hung up before you could join.');
        }
      }

      final stream = await _openLocalMedia(kind);
      if (!_alive(session) || _pendingOffer == null) {
        await _stopTracks(stream);
        throw StateError('Caller hung up before you could join.');
      }
      _localStream = stream;
      if (kind == ChatCallKind.video) {
        localRenderer?.srcObject = _localStream;
      }

      final pc = await _createPeer(session);
      if (!_alive(session) || _pendingOffer == null) {
        try {
          await pc.close();
          await pc.dispose();
        } catch (_) {}
        throw StateError('Caller hung up before you could join.');
      }
      _pc = pc;
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      await _pc!.setRemoteDescription(offer);
      await _flushPendingIce();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      if (!_alive(session)) {
        throw StateError('Caller hung up before you could join.');
      }
      await _sendSignal(
        'call_answer',
        metadata: {
          'sdp': {'type': answer.type, 'sdp': answer.sdp},
        },
      );
      if (!_alive(session)) return;
      _pendingOffer = null;
      _pendingOfferReceivedAt = null;
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    } catch (e) {
      if (!_alive(session)) {
        if (e is StateError) rethrow;
        return;
      }
      await _tearDownMedia();
      await _dismissUi();
      if (e is StateError) rethrow;
      throw StateError(_friendlyJoinError(e));
    }
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

  /// Hang up: dismiss UI immediately, then tear down media / signal in background.
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
    final callerId = _callerId ?? myUserId;
    final callerName = _callerName.isEmpty ? myName : _callerName;
    final callKind = kind == ChatCallKind.video ? 'video' : 'voice';

    // Invalidate any in-flight getUserMedia / peer setup RIGHT NOW.
    _session++;
    _pendingOffer = null;
    _pendingOfferReceivedAt = null;

    await _dismissUi();

    unawaited(() async {
      try {
        final result = await _sendSignal(
          'call_end',
          metadata: {
            'call_log': {
              'status': status,
              'caller_id': callerId,
              'caller_name': callerName,
              'duration_seconds': duration,
              'call_kind': callKind,
            },
          },
        );
        final log = result?['call_log'];
        if (log is Map && onCallLog != null) {
          onCallLog!(
            ChatMessage.fromJson(Map<String, dynamic>.from(log), myUserId: myUserId),
          );
        }
      } catch (_) {}
      await _tearDownMedia();
    }());
  }

  Future<void> handleMessage(ChatMessage msg) async {
    if (_disposed) return;
    if (!msg.type.startsWith('call') || msg.type == 'call_log') return;
    if (_processedIds.contains(msg.id)) return;
    _processedIds.add(msg.id);
    if (_processedIds.length > 400) {
      _processedIds.clear();
    }

    if (msg.type == 'call_end') {
      _session++;
      _pendingOffer = null;
      _pendingOfferReceivedAt = null;
      await _dismissUi();
      unawaited(_tearDownMedia());
      return;
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

    if (msg.type == 'call_answer' && msg.senderId == myUserId) {
      if (state == ChatCallState.incoming || state == ChatCallState.calling) {
        _session++;
        await _dismissUi();
        unawaited(_tearDownMedia());
      }
      return;
    }

    if (msg.type == 'call_offer' && msg.senderId != null && msg.senderId != myUserId) {
      if (_isAncientOffer(msg)) return;
      if (state == ChatCallState.active || state == ChatCallState.calling) return;

      final offer = _sdpFromMeta(meta['sdp']);
      if (offer == null) return;

      await _ringtone.stop();
      kind = meta['call_kind'] == 'video' ? ChatCallKind.video : ChatCallKind.voice;
      _callerId = msg.senderId;
      _callerName = peerName.isNotEmpty ? peerName : 'Caller';
      _pendingOffer = offer;
      _pendingOfferReceivedAt = DateTime.now();
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
