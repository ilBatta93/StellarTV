import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_focusable.dart';
import '../services/image_warmup_service.dart';

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
  int _sectionCount = -1;
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

  /// Last vertical move: held arrows repeat faster than a TV box can lay
  /// out a full-height row, so extra repeats are absorbed instead of queued.
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);
  static const _repeatGap = Duration(milliseconds: 140);

  void _show(int index) {
    if (!mounted || !_scroll.hasClients || !_extent.isFinite) return;
    if (widget.sections.isEmpty) return;
    index = index.clamp(0, widget.sections.length - 1);
    _active = index;
    try {
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo((index * _extent).clamp(0.0, max < 0 ? 0.0 : max));
    } catch (_) {
      // Layout changed between key press and frame: next frame realigns.
    }
  }

  KeyEventResult _move(int index, KeyEvent event) {
    final key = event.logicalKey;
    final count = widget.sections.length;
    final next = index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1);
    if (next < 0) return KeyEventResult.ignored;
    if (next >= count || next >= _rows.length) return KeyEventResult.handled;
    final now = DateTime.now();
    if (event is KeyRepeatEvent && now.difference(_lastMove) < _repeatGap) {
      return KeyEventResult.handled;
    }
    _lastMove = now;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary.context != null) _selected[index] = primary;
    final stops = _rows[next].traversalDescendants
        .where(
          (n) => n.canRequestFocus && n.context != null && n.context!.mounted,
        )
        .toList(growable: false);
    final selectors = stops.whereType<TvHomeSelectorNode>().toList();
    final saved = _selected[next];
    final fromSelectorUp =
        key == LogicalKeyboardKey.arrowUp && primary is TvHomeSelectorNode;
    final FocusNode? target;
    if (fromSelectorUp) {
      target = stops.where((n) => n is! TvHomeSelectorNode).firstOrNull;
    } else if (selectors.isNotEmpty) {
      target =
          selectors.where((n) => n.selected).firstOrNull ?? selectors.first;
    } else {
      // Rows shift when Home gains a section (e.g. after watching a film):
      // a remembered poster may now live in another row.
      target = saved != null && stops.contains(saved)
          ? saved
          : stops.firstOrNull;
    }
    if (target != null) {
      _show(next);
      target.requestFocus();
    }
    return KeyEventResult.handled;
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
    if (_sectionCount != widget.sections.length) {
      _sectionCount = widget.sections.length;
      _selected.clear();
      _active = widget.sections.isEmpty
          ? 0
          : _active.clamp(0, widget.sections.length - 1);
    }
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
          // Neighbouring rows only: building every row offscreen decoded all
          // posters at once and exhausted TV memory under load.
          cacheExtent: _extent,
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
              RemoteNavigation.note();
              try {
                return _move(index, event);
              } catch (error, stack) {
                // Sections changed while the key was handled (background
                // index ready, history update): never let it close the app.
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: error,
                    stack: stack,
                    library: 'tv_home_rows',
                    silent: true,
                  ),
                );
                return KeyEventResult.handled;
              }
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: widget.sections[index],
            ),
          ),
        );
      },
    );
  }
}
