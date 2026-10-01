import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Six separate boxes for an email or authenticator code.
class OtpCodeBoxes extends StatefulWidget {
  const OtpCodeBoxes({super.key, required this.controller, this.onCompleted});

  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpCodeBoxes> createState() => _OtpCodeBoxesState();
}

class _OtpCodeBoxesState extends State<OtpCodeBoxes> {
  static const _length = 6;
  late final List<TextEditingController> _boxes;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _boxes = List.generate(_length, (_) => TextEditingController());
    _nodes = List.generate(_length, (_) => FocusNode());
    _paintFromParent();
    widget.controller.addListener(_paintFromParent);
  }

  @override
  void didUpdateWidget(OtpCodeBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_paintFromParent);
      widget.controller.addListener(_paintFromParent);
      _paintFromParent();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_paintFromParent);
    for (final box in _boxes) {
      box.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _paintFromParent() {
    final digits = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    final current = _boxes.map((box) => box.text).join();
    if (digits == current) return;
    for (var i = 0; i < _length; i++) {
      final char = i < digits.length ? digits[i] : '';
      if (_boxes[i].text != char) {
        _boxes[i].value = TextEditingValue(
          text: char,
          selection: TextSelection.collapsed(offset: char.length),
        );
      }
    }
  }

  void _writeParent() {
    final next = _boxes.map((box) => box.text).join();
    if (widget.controller.text != next) {
      widget.controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
    if (next.length == _length) {
      widget.onCompleted?.call(next);
    }
  }

  void _applyDigits(String raw, int start) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      _boxes[start].clear();
      _writeParent();
      return;
    }
    for (var offset = 0; offset < digits.length && start + offset < _length; offset++) {
      _boxes[start + offset].text = digits[offset];
    }
    final nextIndex = (start + digits.length).clamp(0, _length - 1);
    _nodes[nextIndex].requestFocus();
    _writeParent();
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Row(
        children: [
          for (var index = 0; index < _length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 56,
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.backspace &&
                        _boxes[index].text.isEmpty &&
                        index > 0) {
                      _boxes[index - 1].clear();
                      _nodes[index - 1].requestFocus();
                      _writeParent();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _boxes[index],
                    focusNode: _nodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (value) {
                      final digits = value.replaceAll(RegExp(r'\D'), '');
                      if (digits.length <= 1) {
                        if (digits.isNotEmpty && index < _length - 1) {
                          _nodes[index + 1].requestFocus();
                        }
                        _writeParent();
                        return;
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _applyDigits(digits, index);
                      });
                    },
                    onTap: () => _boxes[index].selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _boxes[index].text.length,
                    ),
                    onSubmitted: (_) {
                      if (index < _length - 1) _nodes[index + 1].requestFocus();
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
