import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'category_dialogs.dart';
import 'tv_focusable.dart';

/// "Aggiungi a categoria" on film and series pages: toggles the title in the
/// user's personal categories, or creates a new one on the spot.
class CategoryAssignButton extends StatefulWidget {
  const CategoryAssignButton({super.key, required this.item});
  final Channel item;

  @override
  State<CategoryAssignButton> createState() => _CategoryAssignButtonState();
}

class _CategoryAssignButtonState extends State<CategoryAssignButton> {
  ContentType get _type => widget.item.type == ContentType.movie
      ? ContentType.movie
      : ContentType.series;

  Future<void> _open() async {
    final app = context.read<AppProvider>();
    if (!mounted) return;
    while (mounted) {
      final customs = app.customCategoriesOf(_type);
      const create = '__new__';
      final chosen = await pickCategoryAction<String>(
        // ignore: use_build_context_synchronously
        context,
        title: 'Aggiungi a categoria',
        actions: [
          for (final c in customs)
            CategoryAction(
              c.id,
              app.isInCustomCategory(c.id, widget.item)
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              c.name,
            ),
          const CategoryAction(
            create,
            Icons.add_circle_outline_rounded,
            'Nuova categoria…',
          ),
        ],
      );
      if (chosen == null || !mounted) return;
      if (chosen == create) {
        final name = await askCategoryName(context, title: 'Nuova categoria');
        if (name == null || !mounted) continue;
        final failure = await app.createCustomCategory(_type, name);
        if (failure != null) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(failure)));
          }
          continue;
        }
        final created = app.customCategoriesOf(_type).last;
        await app.toggleInCustomCategory(created.id, widget.item);
      } else {
        await app.toggleInCustomCategory(chosen, widget.item);
      }
      // Reopen so several categories can be ticked in a row; Back closes.
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final inAny = app
        .customCategoriesOf(_type)
        .any((c) => c.itemIds.contains(widget.item.id));
    return TvFocusable(
      onPressed: _open,
      child: OutlinedButton.icon(
        onPressed: _open,
        icon: Icon(
          inAny ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
          color: inAny ? AppColors.primary : AppColors.textPrimary,
        ),
        label: const Text('Aggiungi a categoria'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
