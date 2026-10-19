import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'tv_focusable.dart';
import 'tv_text_field.dart';

/// Remote-friendly name prompt: OK on the field opens the keyboard, the
/// buttons below are reachable with Down. Returns null when cancelled.
Future<String?> askCategoryName(
  BuildContext context, {
  required String title,
  String initial = '',
  String? Function(String)? validate,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            final message = validate?.call(controller.text);
            if (message != null) {
              setState(() => error = message);
              return;
            }
            Navigator.pop(ctx, controller.text.trim());
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: TvTextField(
                controller: controller,
                autofocus: true,
                maxLength: 40,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: 'Nome della categoria',
                  errorText: error,
                ),
              ),
            ),
            actions: [
              TvFocusable(
                onPressed: () => Navigator.pop(ctx),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annulla'),
                ),
              ),
              TvFocusable(
                onPressed: submit,
                child: FilledButton(
                  onPressed: submit,
                  child: const Text('Salva'),
                ),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

class CategoryAction<T> {
  const CategoryAction(this.value, this.icon, this.label, {this.danger = false});
  final T value;
  final IconData icon;
  final String label;
  final bool danger;
}

/// Vertical action list: each row is one remote focus stop.
Future<T?> pickCategoryAction<T>(
  BuildContext context, {
  required String title,
  required List<CategoryAction<T>> actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, a) in actions.indexed)
                TvFocusable(
                  autofocus: i == 0,
                  focusedScale: 1,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () => Navigator.pop(ctx, a.value),
                  child: ListTile(
                    leading: Icon(
                      a.icon,
                      color: a.danger ? AppColors.error : AppColors.primary,
                    ),
                    title: Text(
                      a.label,
                      style: TextStyle(
                        color: a.danger ? AppColors.error : null,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, a.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
