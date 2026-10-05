import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'tv_focusable.dart';

/// TV drawer shares selection semantics with touch but restores the exact
/// remote target on dismissal, rather than re-entering the top navigation.
class TvCategoryPanel extends StatelessWidget {
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
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack)) {
        onClose();
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
                    autofocus: true,
                    onPressed: onClose,
                    child: IconButton(
                      tooltip: 'Chiudi categorie',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories.entries.elementAt(index);
                  final active = selected == category.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TvFocusable(
                      autofocus: active || (selected == null && index == 0),
                      focusedScale: 1,
                      onPressed: () {
                        onSelected(category.key);
                        onClose();
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
                          onSelected(category.key);
                          onClose();
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
