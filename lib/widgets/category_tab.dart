import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import 'tv_focusable.dart';

class CategoryTab extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const CategoryTab({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DeviceTypeService.isTv ? 56 : 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final label = isAll ? 'Tutti' : categories[index - 1];
          final isSelected = isAll ? selected == null : selected == label;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TvFocusable(
              onPressed: () => onSelected(isAll ? null : label),
              borderRadius: BorderRadius.circular(20),
              child: GestureDetector(
                onTap: () => onSelected(isAll ? null : label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: DeviceTypeService.isTv ? 17 : 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
