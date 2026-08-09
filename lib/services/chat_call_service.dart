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
    this.onCallError,
  });

  final AppStore store;
  final int conversationId;
  final int myUserId;
  final String myName;
  final void Function(ChatMessage message)? onCallLog;
  final void Function(String message)? onCallError;

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
  /// When the offer was created on the server (preferred TTL clock).
  DateTime? _pendingOfferCreatedAt;
  final Set<int> _processedIds = {};
  final ListQueue<RTCIceCandidate> _pendingRemoteIce = ListQueue();
  final ListQueue<ChatMessage> _signalQueue = ListQueue();
  final List<Map<String, dynamic>> _pendingIceOut = [];
  Timer? _iceFlushTimer;
  Timer? _ringExpireTimer;
  bool _iceFlushInFlight = false;
  bool _drainingSignals = false;
  /// True while we are answering on THIS device, so our own `call_answer`
  /// echoing back through polling is not mistaken for "answered elsewhere".
  bool _answeringHere = false;
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
    _iceFlushTimer?.cancel();
    _iceFlushTimer = null;
    _ringExpireTimer?.cancel();
    _ringExpireTimer = null;
    _pendingIceOut.clear();
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
    _iceFlushTimer?.cancel();
    _iceFlushTimer = null;
    _pendingIceOut.clear();
    _pendingRemoteIce.clear();
    _pendingOffer = null;
    _pendingOfferReceivedAt = null;
    _pendingOfferCreatedAt = null;
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
    _ringExpireTimer?.cancel();
    _ringExpireTimer = null;
    await _ringtone.stop();
    if (state != ChatCallState.idle) {
      state = ChatCallState.idle;
      notifyListeners();
    } else {
      state = ChatCallState.idle;
    }
  }

  DateTime? get _offerClock => _pendingOfferCreatedAt ?? _pendingOfferReceivedAt;

  bool get _offerExpired {
    final clock = _offerClock;
    if (clock == null) return false;
    return DateTime.now().difference(clock) > _ringTtl;
  }

  void _armRingExpire() {
    _ringExpireTimer?.cancel();
    final clock = _offerClock;
    if (clock == null) return;
    final remaining = _ringTtl - DateTime.now().difference(clock);
    if (remaining <= Duration.zero) {
      unawaited(_expireIncomingRing());
      return;
    }
    _ringExpireTimer = Timer(remaining, () {
      unawaited(_expireIncomingRing());
    });
  }

  Future<void> _expireIncomingRing() async {
    if (_disposed || state != ChatCallState.incoming) return;
    _session++;
    _pendingOffer = null;
    _pendingOfferReceivedAt = null;
    _pendingOfferCreatedAt = null;
    await _dismissUi();
    unawaited(_tearDownMedia());
    onCallError?.call('Missed call — the ring timed out. Ask them to call again.');
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

  /// Deterministic audio-then-video order. Both peers must build their m-lines
  /// the same way or `setRemoteDescription` rejects the SDP outright.
  List<MediaStreamTrack> _orderedTracks(MediaStream stream) {
    return [...stream.getAudioTracks(), ...stream.getVideoTracks()];
  }

  Future<RTCPeerConnection> _createPeer(int session) async {
    final iceServers = await store.fetchIceServers();
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 2,
    }).timeout(_mediaTimeout);
    pc.onConnectionState = (state) {
      if (!_alive(session)) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _handleConnectionFailed();
      }
    };
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
      // Batch ICE — one POST per candidate floods PHP-FPM and can take the site down.
      _pendingIceOut.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
      _iceFlushTimer ??= Timer(const Duration(milliseconds: 400), () {
        unawaited(_flushOutgoingIce());
      });
    };
    return pc;
  }

  /// ICE gave up: signalling worked but no media path exists between the two
  /// networks. Drop the call with a real reason instead of sitting on a silent
  /// "connected" screen.
  void _handleConnectionFailed() {
    if (_disposed || state == ChatCallState.idle) return;
    onCallError?.call(
      'Call dropped — your networks could not connect. Try Wi-Fi or a stronger signal.',
    );
    unawaited(endCall(
      state == ChatCallState.active
          ? ChatCallEndReason.completed
          : ChatCallEndReason.cancelled,
    ));
  }

  Future<void> _flushOutgoingIce() async {
    _iceFlushTimer?.cancel();
    _iceFlushTimer = null;
    if (_disposed || _pendingIceOut.isEmpty || _iceFlushInFlight) {
      if (!_disposed && _pendingIceOut.isNotEmpty && !_iceFlushInFlight) {
        _iceFlushTimer = Timer(const Duration(milliseconds: 200), () {
          unawaited(_flushOutgoingIce());
        });
      }
      return;
    }

    _iceFlushInFlight = true;
    final batch = List<Map<String, dynamic>>.from(_pendingIceOut);
    _pendingIceOut.clear();
    try {
      await _sendSignal(
        'call_ice',
        metadata: batch.length == 1
            ? {'candidate': batch.first}
            : {'candidates': batch},
      );
    } catch (_) {
      // Drop this batch; peers renegotiate/poll for later candidates.
    } finally {
      _iceFlushInFlight = false;
      if (!_disposed && _pendingIceOut.isNotEmpty) {
        _iceFlushTimer = Timer(const Duration(milliseconds: 200), () {
          unawaited(_flushOutgoingIce());
        });
      }
    }
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
    var description = sdp['sdp']?.toString() ?? '';
    // Nested { sdp: { sdp: '...', type: 'offer' } } from some clients.
    if (description.isEmpty || description == '[object Object]') {
      final nested = _asStringKeyedMap(sdp['sdp']);
      if (nested != null) {
        description = nested['sdp']?.toString() ?? '';
        if ((sdp['type']?.toString() ?? '').trim().isEmpty) {
          sdp['type'] = nested['type'];
        }
      }
    }
    var type = (sdp['type']?.toString() ?? '').trim().toLowerCase();
    // Some peers double-escape newlines when the offer rides JSON → MySQL → JSON.
    if (description.contains(r'\r\n') && !description.contains('\r') && !description.contains('\n')) {
      description = description.replaceAll(r'\r\n', '\n');
    }
    if (description.contains(r'\n') && !description.contains('\n')) {
      description = description.replaceAll(r'\n', '\n');
    }
    description = description
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (description.isEmpty || type.isEmpty) return null;
    if (type != 'offer' && type != 'answer' && type != 'pranswer') return null;
    if (!description.contains('v=0')) return null;
    if (!RegExp(r'^m=(audio|video)\s', multiLine: true).hasMatch(description)) {
      return null;
    }
    return RTCSessionDescription(description, type);
  }

  bool _sdpHasVideo(String? sdp) {
    if (sdp == null || sdp.isEmpty) return false;
    return RegExp(r'^m=video\s', multiLine: true).hasMatch(sdp);
  }

  List<String> _mLineKinds(String? sdp) {
    if (sdp == null || sdp.isEmpty) return const [];
    final kinds = <String>[];
    for (final line in sdp.split('\n')) {
      if (line.startsWith('m=audio')) kinds.add('audio');
      if (line.startsWith('m=video')) kinds.add('video');
    }
    return kinds;
  }

  String? _transceiverMediaKind(RTCRtpTransceiver t, String? fallback) {
    final receiverKind = t.receiver.track?.kind;
    if (receiverKind == 'audio' || receiverKind == 'video') return receiverKind;
    final mid = t.mid.toLowerCase();
    if (mid == 'audio' || mid == '0') return 'audio';
    if (mid == 'video' || mid == '1') return 'video';
    return fallback;
  }

  /// After setRemoteDescription(offer), reuse the offer's transceivers.
  /// Never addTrack here — that invents extra m-lines and createAnswer fails
  /// with the "Call signal was invalid" toast.
  Future<void> _attachLocalTracksForAnswer(
    RTCPeerConnection pc,
    MediaStream stream,
    String? offerSdp,
  ) async {
    List<RTCRtpTransceiver> transceivers = const [];
    for (var attempt = 0; attempt < 6; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 40 * attempt));
      }
      try {
        transceivers = await pc.getTransceivers();
      } catch (_) {
        transceivers = const [];
      }
      if (transceivers.isNotEmpty) break;
    }

    final audios = stream.getAudioTracks();
    final videos = stream.getVideoTracks();
    final mKinds = _mLineKinds(offerSdp);
    var audioIdx = 0;
    var videoIdx = 0;

    for (var i = 0; i < transceivers.length; i++) {
      final t = transceivers[i];
      final fallback = i < mKinds.length ? mKinds[i] : null;
      final kind = _transceiverMediaKind(t, fallback);
      final MediaStreamTrack? track;
      if (kind == 'audio' && audioIdx < audios.length) {
        track = audios[audioIdx++];
      } else if (kind == 'video' && videoIdx < videos.length) {
        track = videos[videoIdx++];
      } else {
        continue;
      }
      try {
        await t.sender.replaceTrack(track);
      } catch (e) {
        debugPrint('CALL_ACCEPT replaceTrack($kind) failed: $e');
        continue;
      }
      try {
        await t.setDirection(TransceiverDirection.SendRecv);
      } catch (_) {}
    }
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
    // The ringback deliberately does NOT start yet: it must never be playing
    // while getUserMedia opens the mic, or the two audio clients fight over the
    // route and Android's audio HAL stalls.
    state = ChatCallState.calling;
    notifyListeners();

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
      for (final track in _orderedTracks(_localStream!)) {
        await _pc!.addTrack(track, _localStream!);
      }

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      if (!_alive(session) || state != ChatCallState.calling) return;

      await _sendSignal(
        'call_offer',
        body: callKind == ChatCallKind.video ? 'Video call' : 'Voice call',
        metadata: {
          // Plain strings only — never send a platform RTCSessionDescription object.
          'sdp': {
            'type': 'offer',
            'sdp': offer.sdp ?? '',
          },
          'call_kind': callKind == ChatCallKind.video ? 'video' : 'voice',
        },
      );
      if (_alive(session) && state == ChatCallState.calling) {
        unawaited(_ringtone.startOutgoing());
      }
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
    if (offer == null || (offer.sdp ?? '').isEmpty) {
      throw StateError('That call is no longer available. Ask them to call again.');
    }
    if (_offerExpired) {
      _session++;
      await _tearDownMedia();
      await _dismissUi();
      throw StateError('That call has expired. Ask them to call again.');
    }

    // Match media to the offer's m-lines (not just call_kind). Opening a camera
    // for an audio-only offer creates an extra video m-line and WebRTC rejects
    // the answer as an "invalid" signal.
    final offerNeedsVideo = _sdpHasVideo(offer.sdp);
    final mediaKind = offerNeedsVideo ? ChatCallKind.video : ChatCallKind.voice;
    kind = mediaKind;

    final session = _session;
    if (!await _ensurePermissions(mediaKind)) {
      throw StateError(
        mediaKind == ChatCallKind.video
            ? 'Camera and microphone permission required'
            : 'Microphone permission required',
      );
    }
    if (!_alive(session) || _pendingOffer == null) {
      throw StateError('Caller hung up before you could join.');
    }

    _answeringHere = true;
    try {
      await _ringtone.stop();
      if (!_alive(session) || _pendingOffer == null) {
        throw StateError('Caller hung up before you could join.');
      }

      if (mediaKind == ChatCallKind.video) {
        await _ensureVideoRenderers(session);
        if (!_alive(session)) {
          throw StateError('Caller hung up before you could join.');
        }
      }

      // Build the peer first and apply the offer before getUserMedia so a bad
      // SDP fails fast with a clear error (instead of after the mic prompt).
      final pc = await _createPeer(session);
      if (!_alive(session) || _pendingOffer == null) {
        try {
          await pc.close();
          await pc.dispose();
        } catch (_) {}
        throw StateError('Caller hung up before you could join.');
      }
      _pc = pc;

      try {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(offer.sdp, 'offer'),
        );
      } catch (e) {
        debugPrint('CALL_ACCEPT setRemoteDescription failed: $e');
        rethrow;
      }

      final stream = await _openLocalMedia(mediaKind);
      if (!_alive(session) || _pendingOffer == null) {
        await _stopTracks(stream);
        throw StateError('Caller hung up before you could join.');
      }
      _localStream = stream;
      if (mediaKind == ChatCallKind.video) {
        localRenderer?.srcObject = _localStream;
      }

      await _attachLocalTracksForAnswer(_pc!, _localStream!, offer.sdp);

      RTCSessionDescription answer;
      try {
        answer = await _pc!.createAnswer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': offerNeedsVideo ? 1 : 0,
        });
        await _pc!.setLocalDescription(answer);
      } catch (e) {
        debugPrint('CALL_ACCEPT createAnswer failed: $e');
        rethrow;
      }

      // ICE after local description — applying early can break answer setup.
      await _flushPendingIce();
      if (!_alive(session)) {
        throw StateError('Caller hung up before you could join.');
      }
      await _sendSignal(
        'call_answer',
        metadata: {
          'sdp': {
            'type': 'answer',
            'sdp': answer.sdp ?? '',
          },
          'call_kind': mediaKind == ChatCallKind.video ? 'video' : 'voice',
        },
      );
      if (!_alive(session)) return;
      _pendingOffer = null;
      _pendingOfferReceivedAt = null;
      _pendingOfferCreatedAt = null;
      _ringExpireTimer?.cancel();
      _ringExpireTimer = null;
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    } catch (e) {
      debugPrint('CALL_ACCEPT failed: $e');
      if (!_alive(session)) {
        if (e is StateError) rethrow;
        return;
      }
      await _tearDownMedia();
      await _dismissUi();
      if (e is StateError) rethrow;
      throw StateError(_friendlyJoinError(e));
    } finally {
      _answeringHere = false;
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
    if (text.contains('timeout')) {
      return 'Joining timed out. Ask them to call again.';
    }
    if (text.contains('setremotedescription') ||
        text.contains('invalid session description') ||
        text.contains('parse') ||
        text.contains('sdp')) {
      return 'Call signal was invalid. Ask them to call again.';
    }
    if (text.contains('createanswer') || text.contains('setlocaldescription')) {
      return 'Could not answer the call. Ask them to call again.';
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
    _pendingOfferCreatedAt = null;
    _ringExpireTimer?.cancel();
    _ringExpireTimer = null;

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
    // Trim the oldest ids rather than clearing: a full clear lets a stale offer
    // be handled twice and ring again after the call is over.
    while (_processedIds.length > 400) {
      _processedIds.remove(_processedIds.first);
    }

    if (msg.type == 'call_end') {
      _session++;
      _pendingOffer = null;
      _pendingOfferReceivedAt = null;
      _pendingOfferCreatedAt = null;
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
      if (!_answeringHere &&
          (state == ChatCallState.incoming || state == ChatCallState.calling)) {
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
      if (offer == null) {
        debugPrint('CALL_OFFER ignored — could not parse SDP metadata');
        return;
      }

      // Same live offer redelivered via poll/WS — keep ICE, don't reset the ring.
      if (state == ChatCallState.incoming &&
          _pendingOffer?.sdp == offer.sdp &&
          _pendingOffer?.type == offer.type) {
        return;
      }

      await _ringtone.stop();
      final fromMeta = meta['call_kind'] == 'video';
      kind = (_sdpHasVideo(offer.sdp) || fromMeta) ? ChatCallKind.video : ChatCallKind.voice;
      _callerId = msg.senderId;
      _callerName = peerName.isNotEmpty ? peerName : 'Caller';
      _pendingOffer = offer;
      _pendingOfferReceivedAt = DateTime.now();
      final created = DateTime.tryParse(msg.createdAt ?? '');
      _pendingOfferCreatedAt = created?.toLocal();
      if (_offerExpired) {
        _pendingOffer = null;
        _pendingOfferReceivedAt = null;
        _pendingOfferCreatedAt = null;
        return;
      }
      _pendingRemoteIce.clear();
      state = ChatCallState.incoming;
      notifyListeners();
      _armRingExpire();
      unawaited(_ringtone.startIncoming());
      return;
    }

    if (msg.type == 'call_ice') {
      final candidates = <Map<String, dynamic>>[];
      final single = _asStringKeyedMap(meta['candidate']);
      if (single != null) candidates.add(single);
      final many = meta['candidates'];
      if (many is List) {
        for (final row in many) {
          final mapped = _asStringKeyedMap(row);
          if (mapped != null) candidates.add(mapped);
        }
      }
      for (final c in candidates) {
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
          continue;
        }
        try {
          await _pc!.addCandidate(ice);
        } catch (_) {}
      }
      return;
    }

    if (_pc == null) return;

    if (msg.type == 'call_answer') {
      final answer = _sdpFromMeta(meta['sdp']);
      if (answer == null) return;
      await _ringtone.stop();
      await _pc!.setRemoteDescription(
        RTCSessionDescription(answer.sdp, 'answer'),
      );
      await _flushPendingIce();
      _startedAt = DateTime.now();
      state = ChatCallState.active;
      notifyListeners();
    }
  }
}
