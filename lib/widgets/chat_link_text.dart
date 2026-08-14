import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/chat_theme.dart';
import '../utils/chat_text_links.dart';

class ChatLinkText extends StatefulWidget {
  const ChatLinkText({
    super.key,
    required this.text,
    required this.mine,
    this.style,
  });

  final String text;
  final bool mine;
  final TextStyle? style;

  @override
  State<ChatLinkText> createState() => _ChatLinkTextState();
}

class _ChatLinkTextState extends State<ChatLinkText> {
  final _recognizers = <GestureRecognizer>[];

  @override
  void didUpdateWidget(covariant ChatLinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openUrl(String raw) async {
    final city = parseCityShopDeepLink(raw);
    if (city != null && mounted) {
      context.push(city.inAppPath);
      return;
    }
    var value = raw.trim();
    if (value.startsWith('www.')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final base = widget.style ??
        TextStyle(
          color: ChatColors.bubbleText,
          height: 1.35,
        );
    final linkColor = ChatColors.link;
    final segments = parseChatText(widget.text);
    if (segments.isEmpty) {
      return Text(widget.text, style: base);
    }

    return Text.rich(
      TextSpan(
        children: [
          for (final segment in segments)
            if (segment.kind == ChatTextKind.plain)
              TextSpan(text: segment.text, style: base)
            else
              TextSpan(
                text: segment.text,
                style: base.copyWith(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                  fontWeight: FontWeight.w700,
                ),
                recognizer: () {
                  final recognizer = TapGestureRecognizer()
                    ..onTap = () {
                      if (segment.kind == ChatTextKind.url) {
                        _openUrl(segment.text);
                      } else {
                        _copy(segment.text.replaceAll(RegExp(r'[\s-]'), ''), 'Number');
                      }
                    };
                  _recognizers.add(recognizer);
                  return recognizer;
                }(),
              ),
        ],
      ),
    );
  }
}
