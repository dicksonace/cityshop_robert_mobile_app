import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

class WatchLiveScreen extends StatefulWidget {
  const WatchLiveScreen({super.key, required this.slug});

  final String slug;

  @override
  State<WatchLiveScreen> createState() => _WatchLiveScreenState();
}

class _WatchLiveScreenState extends State<WatchLiveScreen> {
  bool _loading = true;
  bool _joining = false;
  bool _waitingForHost = false;
  String? _error;
  LivestreamCard? _live;
  WebViewController? _controller;
  Timer? _statusTimer;
  Size? _viewport;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    if (_viewport == null) {
      _viewport = size;
      _load();
    } else if ((_viewport!.width - size.width).abs() > 8 ||
        (_viewport!.height - size.height).abs() > 8) {
      _viewport = size;
    }
  }

  void _startStatusPolling({required bool waitingForHost}) {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      Duration(seconds: waitingForHost ? 3 : 10),
      (_) => _checkStillLive(),
    );
  }

  Future<void> _checkStillLive() async {
    if (!mounted) return;
    try {
      final live = await context.read<AppStore>().fetchLivestream(widget.slug);
      if (!mounted) return;
      if (live == null) {
        _statusTimer?.cancel();
        setState(() {
          _controller = null;
          _joining = false;
          _waitingForHost = false;
          _live = null;
          _error = 'This live has ended.';
        });
        return;
      }
      if (_waitingForHost && live.room != null && live.room!.roomName.isNotEmpty) {
        _statusTimer?.cancel();
        await _openRoom(live);
        return;
      }
      if (_controller != null && (live.room == null || live.room!.roomName.isEmpty)) {
        _statusTimer?.cancel();
        setState(() {
          _controller = null;
          _joining = false;
          _waitingForHost = true;
          _live = live;
          _error = null;
        });
        _startStatusPolling(waitingForHost: true);
      }
    } catch (_) {
      // keep watching; retry next tick
    }
  }

  String _displayName() {
    final user = context.read<AppStore>().user;
    final name = user?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    return 'CityShop shopper';
  }

  Future<void> _load() async {
    _statusTimer?.cancel();
    setState(() {
      _loading = true;
      _joining = false;
      _waitingForHost = false;
      _error = null;
      _controller = null;
    });
    try {
      final live = await context.read<AppStore>().fetchLivestream(widget.slug);
      if (!mounted) return;
      if (live == null) {
        setState(() {
          _live = null;
          _loading = false;
          _waitingForHost = false;
          _error = 'This store is not live right now.';
        });
        return;
      }
      if (live.room == null || live.room!.roomName.isEmpty) {
        setState(() {
          _live = live;
          _loading = false;
          _waitingForHost = true;
          _error = null;
        });
        _startStatusPolling(waitingForHost: true);
        return;
      }

      await _openRoom(live);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _joining = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _joining = false;
        _error = 'Could not open the live video.';
      });
    }
  }

  Future<void> _openRoom(LivestreamCard live) async {
    final mic = await Permission.microphone.request();
    final cam = await Permission.camera.request();
    if (!mounted) return;
    if (!mic.isGranted || !cam.isGranted) {
      setState(() {
        _live = live;
        _loading = false;
        _joining = false;
        _waitingForHost = false;
        _controller = null;
        _error =
            'Camera and microphone permission are required to watch live. Enable them in Settings, then try again.';
      });
      return;
    }

    final size = _viewport ?? MediaQuery.sizeOf(context);
    // Leave room for the app bar; Jitsi needs a real pixel height in WebView (100% often collapses to blank).
    final meetHeight = (size.height - 120).clamp(320.0, 2400.0).round();
    final meetWidth = size.width.round();

    final controller = WebViewController.fromPlatformCreationParams(_webViewParams());
    await _configureWebView(controller);
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (!mounted) return;
            // Ignore subresource noise; only surface main-frame failures.
            if (error.isForMainFrame ?? true) {
              setState(() {
                _joining = false;
                _error = 'Could not load the live video. Check your connection and try again.';
              });
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'CityShopLive',
        onMessageReceived: (message) {
          if (!mounted) return;
          final msg = message.message.trim();
          if (msg == 'joined') {
            setState(() {
              _joining = false;
              _error = null;
            });
          } else if (msg == 'failed') {
            setState(() {
              _joining = false;
              _error = 'Could not join this live room. Try again.';
            });
          }
        },
      );

    await controller.loadHtmlString(
      _jitsiHtml(
        live.room!,
        displayName: _displayName(),
        width: meetWidth,
        height: meetHeight,
      ),
      baseUrl: 'https://${live.room!.domain}/',
    );

    if (!mounted) return;
    setState(() {
      _live = live;
      _controller = controller;
      _loading = false;
      _joining = true;
      _waitingForHost = false;
      _error = null;
    });
    _startStatusPolling(waitingForHost: false);
  }

  PlatformWebViewControllerCreationParams _webViewParams() {
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      return WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      return AndroidWebViewControllerCreationParams();
    }
    return const PlatformWebViewControllerCreationParams();
  }

  Future<void> _configureWebView(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      await platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setOnPlatformPermissionRequest((request) {
        request.grant();
      });
    }
  }

  String _jitsiHtml(
    LivestreamRoom room, {
    required String displayName,
    required int width,
    required int height,
  }) {
    final domain = room.domain.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '');
    final name = room.roomName.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), '');
    final safeName = const JsonEncoder().convert(displayName);
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
  #meet { margin: 0; padding: 0; width: ${width}px; height: ${height}px; max-width: 100%; background: #000; }
  #status {
    position: fixed; left: 0; right: 0; top: 40%; text-align: center;
    color: #fff; font: 600 14px -apple-system, BlinkMacSystemFont, sans-serif;
    opacity: 0.85; pointer-events: none;
  }
</style>
</head>
<body>
<div id="status">Connecting to live…</div>
<div id="meet"></div>
<script src="https://$domain/external_api.js"></script>
<script>
(function () {
  function notify(msg) {
    try { CityShopLive.postMessage(msg); } catch (e) {}
  }
  function hideStatus() {
    var el = document.getElementById("status");
    if (el) el.style.display = "none";
  }
  try {
    if (typeof JitsiMeetExternalAPI !== "function") {
      document.getElementById("status").textContent = "Could not load live video.";
      notify("failed");
      return;
    }
    var api = new JitsiMeetExternalAPI("$domain", {
      roomName: "$name",
      parentNode: document.getElementById("meet"),
      width: $width,
      height: $height,
      userInfo: { displayName: $safeName },
      configOverwrite: {
        prejoinPageEnabled: false,
        startWithAudioMuted: true,
        startWithVideoMuted: true,
        disableDeepLinking: true,
        disableInviteFunctions: true,
        enableWelcomePage: false,
        enableClosePage: false,
        enableLobby: false,
        hideLobbyButton: true,
        requireDisplayName: false,
        disableModeratorIndicator: true,
        p2p: { enabled: false }
      },
      interfaceConfigOverwrite: {
        SHOW_JITSI_WATERMARK: false,
        SHOW_WATERMARK_FOR_GUESTS: false,
        DISABLE_JOIN_LEAVE_NOTIFICATIONS: true,
        MOBILE_APP_PROMO: false,
        AUTHENTICATION_ENABLE: false,
        TOOLBAR_BUTTONS: ["tileview", "fullscreen"]
      }
    });
    api.addListener("videoConferenceJoined", function () {
      hideStatus();
      try { api.executeCommand("setVideoMute", true); } catch (e) {}
      try { api.executeCommand("setAudioMute", true); } catch (e) {}
      try { api.executeCommand("setTileView", true); } catch (e) {}
      notify("joined");
    });
    api.addListener("conferenceFailed", function () {
      document.getElementById("status").textContent = "Could not join this live.";
      notify("failed");
    });
    api.addListener("connectionFailed", function () {
      document.getElementById("status").textContent = "Connection failed.";
      notify("failed");
    });
  } catch (err) {
    document.getElementById("status").textContent = "Could not start live video.";
    notify("failed");
  }
})();
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleSpacing: 8,
        title: Row(
          children: [
            StoreAvatar(
              name: live?.storeName ?? 'Live',
              photo: live?.shopPhoto,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live?.storeName ?? 'Live',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    live?.title?.trim().isNotEmpty == true ? live!.title! : 'Live from the store',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.push('/stores/${widget.slug}'),
            child: const Text('Store', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _loading
          ? const FullPageLoader(label: 'Opening live…')
          : _waitingForHost
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          '${live?.storeName ?? 'The seller'} is going live. The stream will start in a few seconds…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => context.push('/stores/${widget.slug}'),
                          child: const Text('Visit store'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again', style: TextStyle(color: AppColors.accent)),
                        ),
                      ],
                    ),
                  ),
                )
          : _controller == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error ?? 'This store is not live right now.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null && _error!.contains('permission'))
                          ElevatedButton(
                            onPressed: openAppSettings,
                            child: const Text('Open settings'),
                          ),
                        if (_error != null && _error!.contains('permission')) const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => context.push('/stores/${widget.slug}'),
                          child: const Text('Visit store'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again', style: TextStyle(color: AppColors.accent)),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(child: WebViewWidget(controller: _controller!)),
                    if (_joining)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Color(0x99000000),
                            child: FullPageLoader(label: 'Joining live…'),
                          ),
                        ),
                      ),
                    if (_error != null && _controller != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 24,
                        child: Material(
                          color: const Color(0xCC7F1D1D),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StoreAvatar(
                              name: live?.storeName ?? 'Live',
                              photo: live?.shopPhoto,
                              radius: 12,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
