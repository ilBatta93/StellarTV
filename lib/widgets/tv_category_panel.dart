import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'tv_focusable.dart';

/// TV drawer shares selection semantics with touch but restores the exact
/// remote target on dismissal, rather than re-entering the top navigation.
class TvCategoryPanel extends StatefulWidget {
  final Map<String, int> categories;
  final String? selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;
  const TvCategoryPanel({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<TvCategoryPanel> createState() => _TvCategoryPanelState();
}

class _TvCategoryPanelState extends State<TvCategoryPanel> {
  // Approximate row height, enough to build the active row on open.
  static const _rowExtent = 54.0;

  late final int _activeIndex = widget.categories.keys.toList().indexOf(
    widget.selected ?? '',
  );
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _activeIndex > 3 ? (_activeIndex - 3) * _rowExtent : 0,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack)) {
        widget.onClose();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Drawer(
      width: 280,
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(child: Text('Categorie')),
                  TvFocusable(
                    onPressed: widget.onClose,
                    child: IconButton(
                      tooltip: 'Chiudi categorie',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: widget.categories.length,
                itemBuilder: (context, index) {
                  final category = widget.categories.entries.elementAt(index);
                  final active = widget.selected == category.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TvFocusable(
                      // The remote starts on the current choice (or the
                      // first one), never on Close.
                      autofocus: active || (_activeIndex < 0 && index == 0),
                      focusedScale: 1,
                      onPressed: () {
                        widget.onSelected(category.key);
                        widget.onClose();
                      },
                      child: ListTile(
                        dense: true,
                        selected: active,
                        title: Text(
                          category.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text('${category.value}'),
                        onTap: () {
                          widget.onSelected(category.key);
                          widget.onClose();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Left is captured only on the actual left edge, in any visible grid row.
class TvCategoryEdge extends StatelessWidget {
  final Widget child;
  final VoidCallback onOpen;
  final GlobalKey<ScaffoldState> scaffoldKey;
  const TvCategoryEdge({
    super.key,
    required this.child,
    required this.onOpen,
    required this.scaffoldKey,
  });
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent ||
          event.logicalKey != LogicalKeyboardKey.arrowLeft) {
        return KeyEventResult.ignored;
      }
      final item = context.findRenderObject();
      final page = scaffoldKey.currentContext?.findRenderObject();
      if (item is! RenderBox || page is! RenderBox) {
        return KeyEventResult.ignored;
      }
      final left =
          item.localToGlobal(Offset.zero).dx -
          page.localToGlobal(Offset.zero).dx;
      if (left > 48) {
        return KeyEventResult.ignored;
      }
      onOpen();
      return KeyEventResult.handled;
    },
    child: child,
  );
}
