import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'tv_focusable.dart';
import '../services/image_warmup_service.dart';
import '../services/tv_render_policy.dart';

/// Lets the Home banner hand the focus back to the rows.
class TvHomeRowsController {
  _TvHomeRowsState? _state;

  /// Focuses the card last selected in the visible row; false when there
  /// are no rows.
  bool focusCurrent() => _state?._focusCurrent() ?? false;
}

/// Full-height TV sections own vertical focus and keep each horizontal selection.
class TvHomeRows extends StatefulWidget {
  const TvHomeRows({
    super.key,
    required this.sections,
    this.controller,
    this.onExitTop,
  });
  final List<Widget> sections;
  final TvHomeRowsController? controller;

  /// Up from the first row: true when the caller took the focus (the
  /// banner buttons); otherwise the key goes on to the top menu.
  final bool Function()? onExitTop;
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
  final Map<int, ({double offset, double x})> _spots = {};
  double _extent = 0;
  int _active = 0;
  bool _restoring = false;
  int _sectionCount = -1;

  /// Holds the focus while the next row is laid out. Under memory pressure
  /// rows off screen are not built: without a holder the focused card is
  /// disposed by the jump and the focus falls back to whatever the page
  /// focused last (often a banner button).
  final _park = FocusNode(skipTraversal: true);

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
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
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary.context != null) {
      _selected[index] = primary;
      final spot = _spotOf(primary);
      if (spot != null) _spots[index] = spot;
    }
    if (next < 0) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      return widget.onExitTop?.call() == true
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (next >= count || next >= _rows.length) return KeyEventResult.handled;
    final now = DateTime.now();
    if (event is KeyRepeatEvent && now.difference(_lastMove) < _repeatGap) {
      return KeyEventResult.handled;
    }
    _lastMove = now;
    final saved = _selected[next];
    final fromSelectorUp =
        key == LogicalKeyboardKey.arrowUp && primary is TvHomeSelectorNode;
    final stops = _mountedStops(next);
    if (stops.isEmpty) {
      // Under memory pressure the next row is not built until it is shown.
      _focusAfterLayout(
        next,
        fromSelectorUp: fromSelectorUp,
        saved: saved,
        back: index,
      );
      return KeyEventResult.handled;
    }
    _show(next);
    _focusMounted(
      next,
      fromSelectorUp: fromSelectorUp,
      saved: saved,
      stops: stops,
    );
    return KeyEventResult.handled;
  }

  /// Parks the focus, shows row [index] and focuses it once built; if it
  /// never gets a card, goes back to row [back].
  void _focusAfterLayout(
    int index, {
    required bool fromSelectorUp,
    required FocusNode? saved,
    required int back,
    int frames = 4,
  }) {
    _park.requestFocus();
    _show(index);
    void attempt(int left) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Something else took the focus meanwhile: leave it there.
        if (!mounted || !_park.hasPrimaryFocus) return;
        if (index < widget.sections.length && _mountedStops(index).isNotEmpty) {
          _focusMounted(index, fromSelectorUp: fromSelectorUp, saved: saved);
          return;
        }
        if (left > 0) {
          attempt(left - 1);
          WidgetsBinding.instance.scheduleFrame();
          return;
        }
        if (back == index || back >= widget.sections.length) return;
        _show(back);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _park.hasPrimaryFocus) {
            _focusMounted(back, fromSelectorUp: false, saved: _selected[back]);
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      });
    }

    attempt(frames);
  }

  bool _focusCurrent() {
    if (!mounted || widget.sections.isEmpty || _rows.isEmpty) return false;
    final index = _active.clamp(0, widget.sections.length - 1);
    final stops = _mountedStops(index);
    if (stops.isEmpty) {
      _focusAfterLayout(
        index,
        fromSelectorUp: false,
        saved: _selected[index],
        back: index,
      );
      return true;
    }
    _show(index);
    _focusMounted(
      index,
      fromSelectorUp: false,
      saved: _selected[index],
      stops: stops,
    );
    return true;
  }

  List<FocusNode> _mountedStops(int index) {
    if (index < 0 || index >= _rows.length) return const [];
    return _rows[index].traversalDescendants
        .where(
          (n) => n.canRequestFocus && n.context != null && n.context!.mounted,
        )
        .toList(growable: false);
  }

  void _focusMounted(
    int index, {
    required bool fromSelectorUp,
    required FocusNode? saved,
    List<FocusNode>? stops,
  }) {
    final mountedStops = stops ?? _mountedStops(index);
    final selectors = mountedStops.whereType<TvHomeSelectorNode>().toList();
    final FocusNode? target;
    if (fromSelectorUp) {
      target = mountedStops.where((n) => n is! TvHomeSelectorNode).firstOrNull;
    } else if (selectors.isNotEmpty) {
      target =
          selectors.where((n) => n.selected).firstOrNull ?? selectors.first;
    } else if (saved != null && mountedStops.contains(saved)) {
      target = saved;
    } else {
      // The row was rebuilt (memory saving): same scroll, same place.
      final spot = _spots[index];
      final first = mountedStops.firstOrNull;
      final row = first?.context == null
          ? null
          : Scrollable.maybeOf(first!.context!);
      if (spot != null &&
          row != null &&
          row.position.axis == Axis.horizontal &&
          (row.position.pixels - spot.offset).abs() > 0.5) {
        final position = row.position;
        position.jumpTo(
          spot.offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
        _park.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_park.hasPrimaryFocus) return;
          (_nearest(_mountedStops(index), spot.x) ??
                  _mountedStops(index).firstOrNull)
              ?.requestFocus();
        });
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      target = spot == null ? first : _nearest(mountedStops, spot.x) ?? first;
    }
    target?.requestFocus();
  }

  /// Horizontal scroll of the row and centre of the focused card.
  ({double offset, double x})? _spotOf(FocusNode node) {
    final context = node.context;
    final box = context?.findRenderObject();
    if (context == null || box is! RenderBox || !box.attached) return null;
    final row = Scrollable.maybeOf(context);
    final offset = row != null && row.position.axis == Axis.horizontal
        ? row.position.pixels
        : 0.0;
    return (
      offset: offset,
      x: box.localToGlobal(box.size.center(Offset.zero)).dx,
    );
  }

  FocusNode? _nearest(List<FocusNode> stops, double x) {
    FocusNode? best;
    var distance = double.infinity;
    for (final node in stops) {
      if (node is TvHomeSelectorNode) continue;
      final box = node.context?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final d = (box.localToGlobal(box.size.center(Offset.zero)).dx - x).abs();
      if (d < distance) {
        distance = d;
        best = node;
      }
    }
    return best;
  }

  @override
  void didUpdateWidget(covariant TvHomeRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _park.dispose();
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
      _spots.clear();
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
        final list = ListView.builder(
          scrollCacheExtent: ScrollCacheExtent.pixels(
            _extent *
                TvRenderPolicy.rowCacheFraction(
                  memoryPressure: TvImageMemoryGuard.reducedRendering.value,
                ),
          ),
          controller: _scroll,
          physics: const _NoImplicitScroll(),
          padding: EdgeInsets.zero,
          itemExtent: _extent,
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
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              final key = event.logicalKey;
              if (key != LogicalKeyboardKey.arrowDown &&
                  key != LogicalKeyboardKey.arrowUp) {
                return KeyEventResult.ignored;
              }
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
        return Focus(
          focusNode: _park,
          // Keys pressed while a row is being built are dropped, never sent
          // on to the page (which would move the focus somewhere else).
          onKeyEvent: (node, event) =>
              node.hasPrimaryFocus && _arrows.contains(event.logicalKey)
              ? KeyEventResult.handled
              : KeyEventResult.ignored,
          child: list,
        );
      },
    );
  }

  static final _arrows = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };
}
