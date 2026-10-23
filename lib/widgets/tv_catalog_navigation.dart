import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';

/// The menu owns its nodes; catalog sections only request a return to it.
class TvCatalogMenu extends InheritedWidget {
  const TvCatalogMenu({super.key, required this.onMenu, required super.child});
  final VoidCallback onMenu;
  static void focus(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvCatalogMenu>()?.onMenu();
  @override
  bool updateShouldNotify(TvCatalogMenu oldWidget) => false;
}

class TvCatalogItem extends StatelessWidget {
  const TvCatalogItem({
    super.key,
    required this.index,
    required this.columns,
    required this.child,
    this.entry = true,
  });
  final int index;
  final int columns;

  /// False for side widgets (e.g. the Live preview) that must not receive
  /// focus when Down enters the list from the toolbar.
  final bool entry;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// Three explicit regions. Only boundary keys are intercepted; movement
/// inside a grid/list and the Android keyboard retain their normal behavior.
class TvCatalogNavigation extends StatefulWidget {
  const TvCatalogNavigation({
    super.key,
    required this.toolbar,
    required this.filters,
    required this.items,
  });
  final Widget toolbar;
  final Widget filters;
  final Widget items;
  @override
  State<TvCatalogNavigation> createState() => _TvCatalogNavigationState();
}

class _TvCatalogNavigationState extends State<TvCatalogNavigation> {
  final _tools = FocusScopeNode(debugLabel: 'catalog tools');
  final _filters = FocusScopeNode(debugLabel: 'catalog filters');
  final _items = FocusScopeNode(debugLabel: 'catalog items');
  @override
  void initState() {
    super.initState();
  }

  void _first(FocusScopeNode scope) {
    final all = scope.traversalDescendants
        .where((n) => n.canRequestFocus && !n.skipTraversal)
        .toList();
    final entries = all
        .where(
          (n) =>
              n.context
                  ?.findAncestorWidgetOfExactType<TvCatalogItem>()
                  ?.entry !=
              false,
        )
        .toList();
    final ordered = (entries.isEmpty ? all : entries)
      ..sort((a, b) {
        final ar = a.context?.findRenderObject(),
            br = b.context?.findRenderObject();
        if (ar is! RenderBox || br is! RenderBox) return 0;
        final ap = ar.localToGlobal(Offset.zero),
            bp = br.localToGlobal(Offset.zero);
        if ((ap.dy - bp.dy).abs() > 5) return ap.dy.compareTo(bp.dy);
        return ap.dx.compareTo(bp.dx);
      });
    if (ordered.isNotEmpty) ordered.first.requestFocus();
  }

  void _search() {
    final nodes = _tools.traversalDescendants.where(
      (n) => n.debugLabel == 'catalogSearch',
    );
    if (nodes.isNotEmpty) {
      nodes.first.requestFocus();
    } else {
      _first(_tools);
    }
  }

  bool _key(KeyEvent event) {
    if (!DeviceTypeService.isTv ||
        !mounted ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        ModalRoute.of(context)?.isCurrent != true ||
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      return false;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    if (!primary.ancestors.contains(_tools) &&
        !primary.ancestors.contains(_filters) &&
        !primary.ancestors.contains(_items))
      return false;
    if (primary.context
            ?.findAncestorStateOfType<ScaffoldState>()
            ?.isDrawerOpen ==
        true) {
      return false;
    }
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!up && !down) return false;
    final panel = primary.ancestors
        .where((n) => n.debugLabel == 'catalog panel')
        .firstOrNull;
    if (panel != null) return false;
    if (primary.ancestors.contains(_tools)) {
      if (up) {
        if (context.getInheritedWidgetOfExactType<TvCatalogMenu>() != null) {
          TvCatalogMenu.focus(context);
        } else {
          return false;
        }
      } else {
        final panels = _tools.descendants.whereType<FocusScopeNode>().where(
          (n) => n.debugLabel == 'catalog panel',
        );
        if (panels.isNotEmpty) {
          _first(panels.first);
        } else {
          _first(_filters.traversalDescendants.isEmpty ? _items : _filters);
        }
      }
      return true;
    }
    if (primary.ancestors.contains(_filters)) {
      if (up) {
        _search();
      } else {
        _first(_items);
      }
      return true;
    }
    if (up && primary.ancestors.contains(_items)) {
      final item = primary.context
          ?.findAncestorWidgetOfExactType<TvCatalogItem>();
      if (item != null && item.index < item.columns) {
        if (_filters.traversalDescendants.isEmpty) {
          _search();
        } else {
          _first(_filters);
        }
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _tools.dispose();
    _filters.dispose();
    _items.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) =>
        _key(event) ? KeyEventResult.handled : KeyEventResult.ignored,
    child: Column(
      children: [
        FocusScope(node: _tools, child: widget.toolbar),
        FocusScope(node: _filters, child: widget.filters),
        Expanded(
          child: FocusScope(node: _items, child: widget.items),
        ),
      ],
    ),
  );
}

Widget catalogColumn({required List<Widget> children}) {
  if (!DeviceTypeService.isTv) return Column(children: children);
  final last = children.last;
  return TvCatalogNavigation(
    toolbar: children.first,
    filters: Column(children: children.sublist(1, children.length - 1)),
    items: last is Expanded ? last.child : last,
  );
}
