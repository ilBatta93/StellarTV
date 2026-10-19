import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content_type.dart';
import '../models/custom_category.dart';
import '../providers/app_provider.dart';
import '../services/catalog_builder.dart';
import '../theme/app_theme.dart';
import '../widgets/category_dialogs.dart';
import '../widgets/section_row.dart';
import '../widgets/tv_focusable.dart';

enum _Action { up, down, top, contents, rename, delete }

/// Settings → Categorie: reorder playlist categories and create personal
/// ones. OK on a row opens its actions, so every step works with the remote.
class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({super.key});

  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  static const _types = [
    (ContentType.movie, 'Film'),
    (ContentType.series, 'Serie TV'),
    (ContentType.live, 'Diretta'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _types.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Categorie'),
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        tabs: [for (final (_, label) in _types) Tab(text: label)],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [for (final (type, _) in _types) _TypeTab(type: type)],
    ),
  );
}

String _countLabel(CustomCategory c) {
  final n = c.itemIds.length;
  return 'Tua categoria · $n ${n == 1 ? 'titolo' : 'titoli'}';
}

class _TypeTab extends StatelessWidget {
  const _TypeTab({required this.type});
  final ContentType type;

  bool get _allowsCustom => type != ContentType.live;

  Future<void> _create(BuildContext context) async {
    final app = context.read<AppProvider>();
    final name = await askCategoryName(
      context,
      title: 'Nuova categoria',
      validate: (v) => v.trim().isEmpty ? 'Scrivi un nome' : null,
    );
    if (name == null) return;
    final failure = await app.createCustomCategory(type, name);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _open(BuildContext context, String label) async {
    final app = context.read<AppProvider>();
    final custom = app
        .customCategoriesOf(type)
        .where((c) => c.name == label)
        .firstOrNull;
    final order = app.orderedCategoryLabels(type);
    final index = order.indexOf(label);
    final action = await pickCategoryAction<_Action>(
      context,
      title: label,
      actions: [
        if (index > 0)
          const CategoryAction(
            _Action.up,
            Icons.keyboard_arrow_up_rounded,
            'Sposta su',
          ),
        if (index >= 0 && index < order.length - 1)
          const CategoryAction(
            _Action.down,
            Icons.keyboard_arrow_down_rounded,
            'Sposta giù',
          ),
        if (index > 0)
          const CategoryAction(
            _Action.top,
            Icons.vertical_align_top_rounded,
            'Sposta in cima',
          ),
        if (custom != null) ...[
          const CategoryAction(
            _Action.contents,
            Icons.video_library_outlined,
            'Contenuti della categoria',
          ),
          const CategoryAction(
            _Action.rename,
            Icons.edit_outlined,
            'Rinomina',
          ),
          const CategoryAction(
            _Action.delete,
            Icons.delete_outline_rounded,
            'Elimina categoria',
            danger: true,
          ),
        ],
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _Action.up:
        await app.setCategoryOrder(type, moveCategory(order, label, -1));
      case _Action.down:
        await app.setCategoryOrder(type, moveCategory(order, label, 1));
      case _Action.top:
        await app.setCategoryOrder(type, moveCategory(order, label, -index));
      case _Action.contents:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _CustomContents(categoryId: custom!.id),
          ),
        );
      case _Action.rename:
        final name = await askCategoryName(
          context,
          title: 'Rinomina categoria',
          initial: custom!.name,
        );
        if (name == null) return;
        final failure = await app.renameCustomCategory(custom.id, name);
        if (failure != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(failure)));
        }
      case _Action.delete:
        await app.deleteCustomCategory(custom!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final labels = app.orderedCategoryLabels(type);
    final customs = {for (final c in app.customCategoriesOf(type)) c.name: c};
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          _allowsCustom
              ? 'Premi OK su una categoria per spostarla o modificarla. '
                    'Per riempire una tua categoria apri un titolo e scegli '
                    '"Aggiungi a categoria".'
              : 'Premi OK su una categoria per spostarla.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (_allowsCustom)
          TvFocusable(
            autofocus: true,
            focusedScale: 1,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => _create(context),
            child: Card(
              child: ListTile(
                leading: Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Nuova categoria'),
                subtitle: const Text('Crea una tua raccolta di titoli'),
                onTap: () => _create(context),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TvFocusable(
            onPressed: () => app.resetCategoryOrder(type),
            child: TextButton.icon(
              onPressed: () => app.resetCategoryOrder(type),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Ordine originale'),
            ),
          ),
        ),
        if (labels.isEmpty)
          const EmptyState(
            icon: Icons.category_outlined,
            title: 'Nessuna categoria',
            message: 'Carica i contenuti per vedere le categorie.',
          ),
        for (final (i, label) in labels.indexed)
          TvFocusable(
            autofocus: !_allowsCustom && i == 0,
            focusedScale: 1,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => _open(context, label),
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                title: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: customs.containsKey(label)
                    ? Text(_countLabel(customs[label]!))
                    : null,
                trailing: Icon(
                  customs.containsKey(label)
                      ? Icons.star_rounded
                      : Icons.unfold_more_rounded,
                  color: customs.containsKey(label)
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                onTap: () => _open(context, label),
              ),
            ),
          ),
      ],
    );
  }
}

/// Titles inside a personal category; OK removes the focused title.
class _CustomContents extends StatelessWidget {
  const _CustomContents({required this.categoryId});
  final String categoryId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final category = app.customCategories
        .where((c) => c.id == categoryId)
        .firstOrNull;
    final entries = category == null
        ? const <CatalogEntry>[]
        : app.customCategoryEntries(category);
    return Scaffold(
      appBar: AppBar(title: Text(category?.name ?? 'Categoria')),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Categoria vuota',
              message:
                  'Apri un film o una serie e scegli "Aggiungi a categoria".',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Text(
                  'Premi OK su un titolo per toglierlo dalla categoria.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                for (final (i, e) in entries.indexed)
                  TvFocusable(
                    autofocus: i == 0,
                    focusedScale: 1,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () =>
                        app.toggleInCustomCategory(categoryId, e.primary),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          e.primary.displaySeriesName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.remove_circle_outline),
                        onTap: () =>
                            app.toggleInCustomCategory(categoryId, e.primary),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
