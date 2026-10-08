import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ui_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';

class SectionLayoutScreen extends StatelessWidget {
  const SectionLayoutScreen({super.key});

  IconData _icon(AppSection section) => switch (section) {
        AppSection.home => Icons.home_rounded,
        AppSection.live => Icons.live_tv_rounded,
        AppSection.movies => Icons.movie_rounded,
        AppSection.series => Icons.video_library_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    final order = ui.sectionOrder;
    return Scaffold(
      appBar: AppBar(title: const Text('Ordine delle sezioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSection(
            title: 'Sezione iniziale',
            description: 'Scegli cosa mostrare quando apri StellarTV.',
            children: [
              SettingsValueTile(
                icon: Icons.start_rounded,
                title: 'Apri l\'app su',
                value: ui.startSection.label,
                onTap: () async {
                  final chosen = await pickOption<AppSection>(
                    context,
                    title: 'Apri l\'app su',
                    options: order,
                    current: ui.startSection,
                    label: (value) => value.label,
                  );
                  if (chosen != null) await ui.setStartSection(chosen);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'ORDINE',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: order.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              ui.moveSection(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final section = order[index];
              return Card(
                key: ValueKey(section.id),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_icon(section), color: AppColors.primary),
                  title: Text(section.label),
                  subtitle: section == ui.startSection
                      ? const Text('Sezione iniziale')
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Sposta su',
                        onPressed: index == 0
                            ? null
                            : () => ui.moveSection(index, index - 1),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        tooltip: 'Sposta giù',
                        onPressed: index == order.length - 1
                            ? null
                            : () => ui.moveSection(index, index + 1),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: ui.resetSectionLayout,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Ripristina ordine predefinito'),
          ),
        ],
      ),
    );
  }
}
