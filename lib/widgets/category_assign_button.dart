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
class CategoryAssignButton extends StatelessWidget {
  const CategoryAssignButton({super.key, required this.item});
  final Channel item;

  ContentType get _type =>
      item.type == ContentType.movie ? ContentType.movie : ContentType.series;

  Future<void> _open(BuildContext context) async {
    final app = context.read<AppProvider>();
    while (context.mounted) {
      final customs = app.customCategoriesOf(_type);
      const create = '__new__';
      final chosen = await pickCategoryAction<String>(
        context,
        title: 'Aggiungi a categoria',
        actions: [
          for (final c in customs)
            CategoryAction(
              c.id,
              app.isInCustomCategory(c.id, item)
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
      if (chosen == null || !context.mounted) return;
      if (chosen == create) {
        final name = await askCategoryName(context, title: 'Nuova categoria');
        if (name == null || !context.mounted) continue;
        final failure = await app.createCustomCategory(_type, name);
        if (failure != null) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(failure)));
          }
          continue;
        }
        final created = app.customCategoriesOf(_type).last;
        await app.toggleInCustomCategory(created.id, item);
      } else {
        await app.toggleInCustomCategory(chosen, item);
      }
      // Reopen so several categories can be ticked in a row; Back closes.
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final inAny = app
        .customCategoriesOf(_type)
        .any((c) => c.itemIds.contains(item.id));
    return TvFocusable(
      onPressed: () => _open(context),
      child: OutlinedButton.icon(
        onPressed: () => _open(context),
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
