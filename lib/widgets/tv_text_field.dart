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
    this.autofocus = false,
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
  final bool autofocus;

  static Future<void> showKeyboard() async {
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } catch (_) {}
  }

  static const _device = MethodChannel('stellartv/device');

  /// Android TV fallback: asks the system input manager directly.
  static Future<void> showNativeKeyboard() async {
    try {
      await _device.invokeMethod<bool>('showKeyboard');
    } catch (_) {}
  }

  /// Moves focus to [node] and opens the keyboard there.
  static void focusWithKeyboard(FocusNode node) {
    final state = _TvTextFieldState._registry[node];
    if (state != null && DeviceTypeService.isTv) {
      state._beginTvEditing();
      return;
    }
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 150), showKeyboard);
    });
  }

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> with WidgetsBindingObserver {
  static final Map<FocusNode, _TvTextFieldState> _registry = {};
  final FocusNode _own = FocusNode();
  FocusNode get _node => widget.focusNode ?? _own;
  FocusOnKeyEventCallback? _prev;
  bool _tvEditing = false;
  bool _keyboardSeen = false;
  int _showSerial = 0;

  @override
  void initState() {
    super.initState();
    _prev = _node.onKeyEvent;
    _node.onKeyEvent = _onKey;
    _registry[_node] = this;
    _node.addListener(_onFocusChange);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onFocusChange() {
    if (!_node.hasFocus && _tvEditing && mounted) _endTvEditing(hide: false);
  }

  /// TV: OK/click turns the field editable and opens the keyboard. The
  /// field stays focused: EditableText opens the input connection itself
  /// once readOnly turns false, then the keyboard is requested again
  /// (Flutter and native) so slow TV IMEs still show up.
  void _beginTvEditing() {
    if (!DeviceTypeService.isTv) return;
    _keyboardSeen = false;
    final serial = ++_showSerial;
    if (!_tvEditing) setState(() => _tvEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || serial != _showSerial) return;
      // requestFocus grants the keyboard token: if the field was not
      // focused, gaining focus opens the connection and the keyboard.
      if (!_node.hasFocus) _node.requestFocus();
      for (final ms in const [80, 250, 600]) {
        await Future<void>.delayed(Duration(milliseconds: ms));
        if (!mounted || !_tvEditing || serial != _showSerial) return;
        if (!_node.hasFocus) _node.requestFocus();
        if (_keyboardSeen) return;
        await TvTextField.showKeyboard();
        if (ms >= 250) await TvTextField.showNativeKeyboard();
      }
    });
  }

  void _endTvEditing({bool hide = true}) {
    _showSerial++;
    if (hide) SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _keyboardSeen = false;
    if (_tvEditing && mounted) setState(() => _tvEditing = false);
  }

  /// Android consumes Back to close the IME: detect the keyboard closing
  /// and leave edit mode so the D-Pad navigates again.
  @override
  void didChangeMetrics() {
    if (!DeviceTypeService.isTv || !_tvEditing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tvEditing) return;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final inset = views.first.viewInsets.bottom;
      if (inset > 0) {
        _keyboardSeen = true;
      } else if (_keyboardSeen) {
        _endTvEditing(hide: false);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent) {
      final k = e.logicalKey;
      if (DeviceTypeService.isTv &&
          _tvEditing &&
          (k == LogicalKeyboardKey.escape ||
              k == LogicalKeyboardKey.goBack ||
              k == LogicalKeyboardKey.browserBack)) {
        _endTvEditing();
        return KeyEventResult.handled;
      }
      if (DeviceTypeService.isTv && k == LogicalKeyboardKey.arrowDown) {
        node.nextFocus();
        return KeyEventResult.handled;
      }
      if (DeviceTypeService.isTv && k == LogicalKeyboardKey.arrowUp) {
        node.previousFocus();
        return KeyEventResult.handled;
      }
      // D-Pad OK always (re)opens the keyboard: Android may close the IME
      // without notifying Flutter. Enter submits while editing.
      final isOk =
          k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.gameButtonA;
      final isEnter =
          k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;
      if (DeviceTypeService.isTv && (isOk || (isEnter && !_tvEditing))) {
        _beginTvEditing();
        return KeyEventResult.handled;
      }
    }
    return _prev?.call(node, e) ?? KeyEventResult.ignored;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _node.removeListener(_onFocusChange);
    if (_registry[_node] == this) _registry.remove(_node);
    _node.onKeyEvent = _prev;
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      autofocus: widget.autofocus,
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
        if (DeviceTypeService.isTv && mounted) _endTvEditing();
        final next = widget.nextFocus;
        if (next != null) TvTextField.focusWithKeyboard(next);
        widget.onSubmitted?.call(v);
      },
    );
  }
}
