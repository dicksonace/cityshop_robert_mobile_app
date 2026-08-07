import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/chat_call_service.dart';
import '../theme/app_theme.dart';

class ChatCallOverlay extends StatelessWidget {
  const ChatCallOverlay({
    super.key,
    required this.call,
    required this.peerName,
    required this.onAccept,
    required this.onEnd,
  });

  final ChatCallService call;
  final String peerName;
  final VoidCallback onAccept;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: call,
      builder: (context, _) {
        if (call.state == ChatCallState.idle) return const SizedBox.shrink();

        final isVideo = call.kind == ChatCallKind.video;
        final status = switch (call.state) {
          ChatCallState.calling => isVideo ? 'Video calling…' : 'Calling…',
          ChatCallState.incoming => isVideo ? 'Incoming video call' : 'Incoming call',
          ChatCallState.active => isVideo ? 'Video call' : 'On call',
          ChatCallState.idle => '',
        };

        return Material(
          color: Colors.black.withValues(alpha: 0.92),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: Column(
                children: [
                  Text(
                    peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: isVideo &&
                            call.renderersReady &&
                            call.localRenderer != null &&
                            call.remoteRenderer != null &&
                            (call.state == ChatCallState.active || call.state == ChatCallState.calling)
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: RTCVideoView(
                                  call.remoteRenderer!,
                                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 12,
                                width: 110,
                                height: 150,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: RTCVideoView(
                                    call.localRenderer!,
                                    mirror: true,
                                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: AppColors.accent.withValues(alpha: 0.25),
                              child: Icon(
                                isVideo ? Icons.videocam_rounded : Icons.person_rounded,
                                size: 64,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (call.state == ChatCallState.incoming) ...[
                        _RoundAction(
                          color: const Color(0xFF22C55E),
                          icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                          label: 'Accept',
                          onTap: onAccept,
                        ),
                        const SizedBox(width: 36),
                      ],
                      _RoundAction(
                        color: const Color(0xFFEF4444),
                        icon: Icons.call_end_rounded,
                        label: call.state == ChatCallState.incoming ? 'Decline' : 'Hang up',
                        onTap: onEnd,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
