import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/ui_settings.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_focusable.dart';

class SectionLayoutScreen extends StatelessWidget {
  const SectionLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (DeviceTypeService.isTv) return const _TvSectionLayout();
    final ui = context.watch<UiSettings>();
    final order = ui.sectionOrder;
    return Scaffold(
      appBar: AppBar(title: const Text('Ordine delle sezioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _StartSectionTile(ui: ui),
          const SizedBox(height: 16),
          const _OrderLabel(),
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
                  leading: Icon(sectionIcon(section), color: AppColors.primary),
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

IconData sectionIcon(AppSection section) => switch (section) {
      AppSection.home => Icons.home_rounded,
      AppSection.live => Icons.live_tv_rounded,
      AppSection.movies => Icons.movie_rounded,
      AppSection.series => Icons.video_library_rounded,
    };

class _OrderLabel extends StatelessWidget {
  const _OrderLabel();
  @override
  Widget build(BuildContext context) => Text(
        'ORDINE',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
      );
}

class _StartSectionTile extends StatelessWidget {
  final UiSettings ui;
  const _StartSectionTile({required this.ui});

  @override
  Widget build(BuildContext context) => SettingsSection(
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
                options: ui.sectionOrder,
                current: ui.startSection,
                label: (value) => value.label,
              );
              if (chosen != null) await ui.setStartSection(chosen);
            },
          ),
        ],
      );
}

/// TV: one focus stop per section. OK picks the section up, Su/Giù move it,
/// OK or Back drops it. The focus follows the moved section.
class _TvSectionLayout extends StatefulWidget {
  const _TvSectionLayout();
  @override
  State<_TvSectionLayout> createState() => _TvSectionLayoutState();
}

class _TvSectionLayoutState extends State<_TvSectionLayout> {
  final Map<AppSection, FocusNode> _nodes = {
    for (final s in AppSection.values) s: FocusNode(debugLabel: 'section-$s'),
  };
  AppSection? _moving;

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _move(UiSettings ui, AppSection s, int delta) async {
    final order = ui.sectionOrder;
    final from = order.indexOf(s);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= order.length) return;
    await ui.moveSection(from, to);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[s]?.requestFocus();
    });
  }

  KeyEventResult _onKey(UiSettings ui, AppSection s, KeyEvent event) {
    if (_moving != s || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(ui, s, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(ui, s, 1);
      return KeyEventResult.handled;
    }
    // Left/right are blocked while moving so the focus stays on the item.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    final order = ui.sectionOrder;
    return PopScope(
      canPop: _moving == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _moving != null) setState(() => _moving = null);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Ordine delle sezioni')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _StartSectionTile(ui: ui),
            const SizedBox(height: 16),
            const _OrderLabel(),
            const SizedBox(height: 4),
            const Text(
              'Premi OK su una sezione, spostala con Su/Giù e premi di nuovo OK.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < order.length; i++)
              Padding(
                key: ValueKey(order[i].id),
                padding: const EdgeInsets.only(bottom: 8),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (_, e) => _onKey(ui, order[i], e),
                  child: TvFocusable(
                    focusNode: _nodes[order[i]],
                    autofocus: i == 0,
                    focusedScale: 1,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () => setState(
                      () => _moving = _moving == order[i] ? null : order[i],
                    ),
                    child: _row(ui, order[i], i),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TvFocusable(
              focusedScale: 1,
              borderRadius: BorderRadius.circular(12),
              onPressed: () {
                setState(() => _moving = null);
                ui.resetSectionLayout();
              },
              child: OutlinedButton.icon(
                onPressed: ui.resetSectionLayout,
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Ripristina ordine predefinito'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(UiSettings ui, AppSection s, int index) {
    final moving = _moving == s;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: moving
            ? AppColors.primary.withValues(alpha: 0.18)
            : AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            '${index + 1}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          Icon(sectionIcon(s), color: AppColors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (s == ui.startSection)
                  const Text(
                    'Sezione iniziale',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            moving
                ? 'Su/Giù per spostare · OK per confermare'
                : 'OK per spostare',
            style: TextStyle(
              color: moving ? AppColors.primary : AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            moving ? Icons.swap_vert_rounded : Icons.drag_indicator_rounded,
            color: moving ? AppColors.primary : AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
