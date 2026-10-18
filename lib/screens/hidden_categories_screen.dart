import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/content_type.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/section_row.dart';

/// Per-type category visibility editor: switch a category off and it
/// disappears from the catalog pages and the categories drawer.
class HiddenCategoriesScreen extends StatefulWidget {
  const HiddenCategoriesScreen({super.key});

  @override
  State<HiddenCategoriesScreen> createState() => _HiddenCategoriesScreenState();
}

class _HiddenCategoriesScreenState extends State<HiddenCategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _types = [
    (ContentType.live, 'Diretta'),
    (ContentType.movie, 'Film'),
    (ContentType.series, 'Serie TV'),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorie nascoste'),
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
}

class _TypeTab extends StatelessWidget {
  final ContentType type;
  const _TypeTab({required this.type});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final categories = app.categoryOrderOf(type);
    if (categories.isEmpty) {
      return const EmptyState(
        icon: Icons.category_outlined,
        title: 'Nessuna categoria',
        message: 'Carica i contenuti per vedere le categorie.',
      );
    }
    final hidden = app.hiddenCategoriesOf(type).toSet();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Le categorie disattivate non compaiono nei contenuti.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        for (final c in categories)
          tvSettingsRow(
            onPressed: () => _toggle(context, app, c, hidden.contains(c)),
            child: SwitchListTile(
              value: !hidden.contains(c),
              onChanged: (visible) async {
                final next = [...app.hiddenCategoriesOf(type)];
                if (visible) {
                  next.remove(c);
                } else if (!next.contains(c)) {
                  next.add(c);
                }
                await context.read<AppProvider>().setHiddenCategories(
                  type,
                  next,
                );
              },
              title: Text(
                c,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: hidden.contains(c)
                  ? const Text(
                      'Nascosta',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _toggle(
    BuildContext context,
    AppProvider app,
    String category,
    bool visible,
  ) async {
    final next = [...app.hiddenCategoriesOf(type)];
    if (visible) {
      next.remove(category);
    } else if (!next.contains(category)) {
      next.add(category);
    }
    await app.setHiddenCategories(type, next);
  }
}
