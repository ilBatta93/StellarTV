import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'tv_focusable.dart';

class TvFilterOption {
  const TvFilterOption(this.label, this.selected, this.onSelected);
  final String label;
  final bool selected;
  final VoidCallback onSelected;
}

class TvFilterPanel extends StatelessWidget {
  const TvFilterPanel({super.key, required this.options});
  final List<TvFilterOption> options;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 184),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: TvFocusable(
                focusedScale: 1,
                borderRadius: BorderRadius.circular(8),
                onPressed: option.onSelected,
                child: InkWell(
                  onTap: option.onSelected,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: option.selected
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: option.selected
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      option.label,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: option.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: option.selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
