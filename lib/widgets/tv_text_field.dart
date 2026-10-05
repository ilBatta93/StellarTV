import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/device_type_service.dart';

/// TextField usable with a TV remote (Fire TV / Google TV): arrows up/down
/// move between fields, OK/Enter opens the on-screen keyboard, and moving
/// to the next field also opens the keyboard there.
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.nextFocus,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.decoration,
    this.autofillHints,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final FocusNode? nextFocus;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final InputDecoration? decoration;
  final Iterable<String>? autofillHints;

  static void showKeyboard() =>
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');

  /// Moves focus to [node] and opens the keyboard there.
  static void focusWithKeyboard(FocusNode node) {
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 150), showKeyboard);
    });
  }

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  final FocusNode _own = FocusNode();
  FocusNode get _node => widget.focusNode ?? _own;
  FocusOnKeyEventCallback? _prev;
  bool _tvEditing = false;

  @override
  void initState() {
    super.initState();
    _prev = _node.onKeyEvent;
    _node.onKeyEvent = _onKey;
  }

  void _beginTvEditing() {
    if (!DeviceTypeService.isTv) return;
    if (!_tvEditing) setState(() => _tvEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _node.requestFocus();
      TvTextField.showKeyboard();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent) {
      final k = e.logicalKey;
      if (DeviceTypeService.isTv && k == LogicalKeyboardKey.arrowDown) {
        node.nextFocus();
        return KeyEventResult.handled;
      }
      if (DeviceTypeService.isTv && k == LogicalKeyboardKey.arrowUp) {
        node.previousFocus();
        return KeyEventResult.handled;
      }
      if (DeviceTypeService.isTv &&
          (k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.gameButtonA ||
              k == LogicalKeyboardKey.numpadEnter)) {
        _beginTvEditing();
        return KeyEventResult.handled;
      }
    }
    return _prev?.call(node, e) ?? KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _node.onKeyEvent = _prev;
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _node,
      readOnly: DeviceTypeService.isTv && !_tvEditing,
      showCursor: !DeviceTypeService.isTv || _tvEditing,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      onTap: DeviceTypeService.isTv
          ? _beginTvEditing
          : TvTextField.showKeyboard,
      onSubmitted: (v) {
        if (DeviceTypeService.isTv && mounted)
          setState(() => _tvEditing = false);
        final next = widget.nextFocus;
        if (next != null) TvTextField.focusWithKeyboard(next);
        widget.onSubmitted?.call(v);
      },
    );
  }
}
