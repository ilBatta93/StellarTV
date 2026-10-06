import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/device_type_service.dart';
import '../services/tv_remote_keys.dart';
import 'tv_focusable.dart';

/// TextField usable with a TV remote (Fire TV / Google TV).
///
/// Phones and tablets get a plain, always-editable [TextField] (unchanged).
///
/// On TV the field is made of two focus stops:
/// * an outer "shell" that the D-Pad lands on: it is highlighted but does
///   not open the keyboard, so passing over a search bar never pops it up;
/// * the real [TextField], skipped by D-Pad traversal. OK / click moves the
///   focus into it, which is the standard Flutter path (gaining focus opens
///   the input connection and shows the keyboard), the same one used on
///   phones. The field is never read-only, so nothing has to re-open the
///   connection later.
///
/// Back closes the keyboard (Android) and a second Back, or Up/Down, leaves
/// the field and returns to D-Pad navigation.
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
    this.openOnFocus = false,
    this.clearable = false,
    this.onMoveDown,
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
  final bool clearable;
  final VoidCallback? onMoveDown;

  /// TV: open the keyboard as soon as the D-Pad reaches the field (login
  /// and account forms), instead of waiting for OK. After Back closes the
  /// keyboard it is not re-opened until the field is left and reached again.
  final bool openOnFocus;

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
    if (state != null && state.mounted) {
      state._startEditing();
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
  final FocusNode _own = FocusNode(debugLabel: 'TvTextField');
  late final FocusNode _shell = FocusNode(
    debugLabel: 'TvTextField shell',
    onKeyEvent: _onShellKey,
  );
  late FocusNode _node;
  FocusOnKeyEventCallback? _prev;
  bool _keyboardSeen = false;
  int _serial = 0;

  bool get _tv => DeviceTypeService.isTv;
  bool get _editing => _node.hasFocus;

  @override
  void initState() {
    super.initState();
    _attach(widget.focusNode ?? _own);
    _shell.addListener(_onShellFocus);
    widget.controller.addListener(_rebuild);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant TvTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
    final next = widget.focusNode ?? _own;
    if (next != _node) {
      _detach();
      _attach(next);
    }
  }

  void _attach(FocusNode node) {
    _node = node;
    _prev = node.onKeyEvent;
    node.onKeyEvent = _onFieldKey;
    // D-Pad traversal stops on the shell, never directly on the field.
    if (_tv) node.skipTraversal = true;
    node.addListener(_onFieldFocus);
    _registry[node] = this;
  }

  void _detach() {
    _node.removeListener(_onFieldFocus);
    if (_registry[_node] == this) _registry.remove(_node);
    _node.onKeyEvent = _prev;
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool _suppressAuto = false;

  void _onShellFocus() {
    if (!_shell.hasFocus) _suppressAuto = false;
    if (_tv && widget.openOnFocus && !_suppressAuto && _shell.hasPrimaryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _shell.hasPrimaryFocus && !_suppressAuto) {
          _startEditing();
        }
      });
    }
    _rebuild();
  }

  void _onFieldFocus() {
    if (_tv) {
      // Registered before the TextField's own listener: Android learns that a
      // text editor is active before Flutter opens the keyboard connection.
      if (_node.hasFocus) {
        TvRemoteKeys.reportEditing(true);
      } else {
        TvRemoteKeys.recheckEditing();
      }
    }
    if (!_node.hasFocus) {
      _serial++;
      _keyboardSeen = false;
    }
    _rebuild();
  }

  /// Focuses the real field: Flutter opens the input connection and shows
  /// the keyboard. The show request is repeated (Flutter + native) because
  /// some TV keyboards ignore the first one.
  void _startEditing() {
    final serial = ++_serial;
    _keyboardSeen = false;
    if (_tv) TvRemoteKeys.reportEditing(true);
    if (!_node.hasFocus) _node.requestFocus();
    if (!_tv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final ms in const [120, 350, 800]) {
        await Future<void>.delayed(Duration(milliseconds: ms));
        if (!mounted || serial != _serial || !_node.hasFocus) return;
        if (_keyboardSeen) return;
        await TvTextField.showKeyboard();
        if (ms >= 350) await TvTextField.showNativeKeyboard();
      }
    });
  }

  /// Leaves the field: focus goes back to the shell, Flutter closes the
  /// input connection and hides the keyboard.
  void _stopEditing() {
    _suppressAuto = true;
    _serial++;
    _keyboardSeen = false;
    if (_shell.context != null) _shell.requestFocus();
  }

  /// Android consumes Back to close the IME: when the keyboard disappears,
  /// leave the field so the D-Pad navigates again.
  @override
  void didChangeMetrics() {
    if (!_tv || !_editing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final inset = views.first.viewInsets.bottom;
      if (inset > 0) {
        _keyboardSeen = true;
      } else if (_keyboardSeen) {
        _stopEditing();
      }
    });
  }

  static bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  static bool _isBack(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.escape ||
      k == LogicalKeyboardKey.goBack ||
      k == LogicalKeyboardKey.browserBack;

  /// Keys on the highlighted (not editing) field.
  KeyEventResult _onShellKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (e is KeyDownEvent && _isOk(k)) {
      _startEditing();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (widget.onMoveDown != null) {
        widget.onMoveDown?.call();
        return KeyEventResult.ignored;
      }
      node.nextFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      node.previousFocus();
      return KeyEventResult.handled;
    }
    return _prev?.call(node, e) ?? KeyEventResult.ignored;
  }

  /// Keys while the real field is focused (keyboard open or just closed).
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent e) {
    if (_tv && e is KeyDownEvent) {
      final k = e.logicalKey;
      if (_isBack(k)) {
        _stopEditing();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        _stopEditing();
        if (widget.onMoveDown != null) {
          widget.onMoveDown?.call();
          return KeyEventResult.ignored;
        }
        _shell.nextFocus();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        _stopEditing();
        _shell.previousFocus();
        return KeyEventResult.handled;
      }
      // D-Pad OK re-opens a keyboard Android closed without telling us.
      if (k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.gameButtonA) {
        _startEditing();
        TvTextField.showKeyboard();
        return KeyEventResult.handled;
      }
    }
    return _prev?.call(node, e) ?? KeyEventResult.ignored;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    WidgetsBinding.instance.removeObserver(this);
    _detach();
    _shell.removeListener(_onShellFocus);
    _shell.dispose();
    _own.dispose();
    super.dispose();
  }

  void _submitted(String v) {
    final next = widget.nextFocus;
    if (next != null) {
      TvTextField.focusWithKeyboard(next);
    } else if (_tv && mounted) {
      _stopEditing();
    }
    widget.onSubmitted?.call(v);
  }

  Widget _field({InputDecoration? decoration, bool autofocus = false}) {
    return TextField(
      autofocus: autofocus,
      controller: widget.controller,
      focusNode: _node,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      decoration: decoration,
      onChanged: widget.onChanged,
      onTap: _tv ? _startEditing : TvTextField.showKeyboard,
      onSubmitted: _submitted,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_tv) {
      return _field(decoration: widget.decoration, autofocus: widget.autofocus);
    }
    final theme = Theme.of(context);
    final highlighted = _shell.hasPrimaryFocus;
    var decoration = widget.decoration ?? const InputDecoration();
    if (widget.clearable && widget.controller.text.isNotEmpty) {
      void clear() {
        widget.controller.clear();
        widget.onChanged?.call('');
      }

      decoration = decoration.copyWith(
        suffixIcon: TvFocusable(
          focusedScale: 1,
          onPressed: clear,
          child: IconButton(
            tooltip: 'Cancella ricerca',
            onPressed: clear,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ),
      );
    }
    if (highlighted) {
      final border =
          theme.inputDecorationTheme.focusedBorder ??
          OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          );
      final side = border.borderSide.copyWith(
        color: theme.colorScheme.primary,
        width: 2.5,
      );
      decoration = decoration.copyWith(
        enabledBorder: border.copyWith(borderSide: side),
        border: border.copyWith(borderSide: side),
      );
    }
    return Focus(
      focusNode: _shell,
      autofocus: widget.autofocus,
      child: AnimatedScale(
        scale: highlighted ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: _field(decoration: decoration),
      ),
    );
  }
}
