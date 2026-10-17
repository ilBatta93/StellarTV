import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-height TV sections own vertical focus and keep each horizontal selection.
class TvHomeRows extends StatefulWidget {
  const TvHomeRows({super.key, required this.sections});
  final List<Widget> sections;
  @override
  State<TvHomeRows> createState() => _TvHomeRowsState();
}

class _NoImplicitScroll extends ClampingScrollPhysics {
  const _NoImplicitScroll();
  @override
  bool get allowImplicitScrolling => false;
}

class _TvHomeRowsState extends State<TvHomeRows> {
  final _scroll = ScrollController();
  final List<FocusNode> _rows = [];
  final Map<int, FocusNode> _selected = {};
  double _extent = 0;
  int _active = 0;
  bool _restoring = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_restoring || !_scroll.hasClients) return;
      final expected = (_active * _extent).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if ((_scroll.offset - expected).abs() < 0.5) return;
      _restoring = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _show(_active);
        _restoring = false;
      });
    });
  }

  void _show(int index) {
    _active = index;
    if (_scroll.hasClients)
      _scroll.jumpTo(
        (index * _extent).clamp(0.0, _scroll.position.maxScrollExtent),
      );
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _rows) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    while (_rows.length < widget.sections.length) {
      _rows.add(FocusNode(debugLabel: 'home-row-${_rows.length}'));
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        _extent = bounds.maxHeight;
        return ListView.builder(
          controller: _scroll,
          physics: const _NoImplicitScroll(),
          padding: EdgeInsets.zero,
          itemExtent: _extent,
          cacheExtent: _extent * widget.sections.length,
          itemCount: widget.sections.length,
          itemBuilder: (context, index) => Focus(
            focusNode: _rows[index],
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) {
              if (focused) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _show(index);
                });
              }
            },
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent)
                return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key != LogicalKeyboardKey.arrowDown &&
                  key != LogicalKeyboardKey.arrowUp)
                return KeyEventResult.ignored;
              final next =
                  index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1);
              if (next < 0) return KeyEventResult.ignored;
              if (next >= widget.sections.length) return KeyEventResult.handled;
              final primary = FocusManager.instance.primaryFocus;
              if (primary != null) _selected[index] = primary;
              final saved = _selected[next];
              final target =
                  saved != null &&
                      saved.context != null &&
                      saved.canRequestFocus
                  ? saved
                  : _rows[next].traversalDescendants
                        .where((n) => n.canRequestFocus)
                        .firstOrNull;
              if (target != null) {
                _show(next);
                target.requestFocus();
              }
              return KeyEventResult.handled;
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: widget.sections[index],
            ),
          ),
        );
      },
    );
  }
}
