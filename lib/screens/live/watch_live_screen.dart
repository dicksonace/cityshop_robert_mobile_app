import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
  String? _error;
  LivestreamCard? _live;
  WebViewController? _controller;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkStillLive());
  }

  Future<void> _checkStillLive() async {
    if (!mounted || _controller == null) return;
    try {
      final live = await context.read<AppStore>().fetchLivestream(widget.slug);
      if (!mounted) return;
      if (live == null || live.room == null || live.room!.roomName.isEmpty) {
        _statusTimer?.cancel();
        setState(() {
          _controller = null;
          _live = live;
          _error = 'This live has ended.';
        });
      }
    } catch (_) {
      // keep watching; retry next tick
    }
  }

  Future<void> _load() async {
    _statusTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _controller = null;
    });
    try {
      final live = await context.read<AppStore>().fetchLivestream(widget.slug);
      if (!mounted) return;
      if (live == null || live.room == null || live.room!.roomName.isEmpty) {
        setState(() {
          _live = live;
          _loading = false;
          _error = 'This store is not live right now.';
        });
        return;
      }
      await Permission.microphone.request();
      await Permission.camera.request();
      if (!mounted) return;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black);
      _enableMedia(controller);
      await controller.loadHtmlString(
        _jitsiHtml(live.room!),
        baseUrl: 'https://${live.room!.domain}/',
      );
      setState(() {
        _live = live;
        _controller = controller;
        _loading = false;
      });
      _startStatusPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open the live video.';
      });
    }
  }

  void _enableMedia(WebViewController controller) {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setOnPlatformPermissionRequest((request) {
        request.grant();
      });
    }
  }

  String _jitsiHtml(LivestreamRoom room) {
    final domain = room.domain.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '');
    final name = room.roomName.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), '');
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body, #meet { margin: 0; padding: 0; height: 100%; width: 100%; background: #000; overflow: hidden; }
</style>
</head>
<body>
<div id="meet"></div>
<script src="https://meet.jit.si/external_api.js"></script>
<script>
  const api = new JitsiMeetExternalAPI("$domain", {
    roomName: "$name",
    parentNode: document.getElementById("meet"),
    width: "100%",
    height: "100%",
    userInfo: { displayName: "CityShop shopper" },
    configOverwrite: {
      prejoinPageEnabled: false,
      startWithAudioMuted: true,
      startWithVideoMuted: true,
      disableDeepLinking: true,
      disableInviteFunctions: true
    },
    interfaceConfigOverwrite: {
      SHOW_JITSI_WATERMARK: false,
      TOOLBAR_BUTTONS: ["microphone", "camera", "tileview", "fullscreen"]
    }
  });
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
                    WebViewWidget(controller: _controller!),
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
