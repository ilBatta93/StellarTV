import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog_start_category.dart';
import '../models/content_type.dart';
import '../providers/app_provider.dart';
import '../services/catalog_view_memory.dart';
import 'settings_tiles.dart';

/// Impostazioni → Categorie: the category Diretta, Film and Serie TV open
/// on. Stored on this device only (labels come from the user's source).
class CatalogStartTiles extends StatefulWidget {
  const CatalogStartTiles({super.key});

  @override
  State<CatalogStartTiles> createState() => _CatalogStartTilesState();
}

class _CatalogStartTilesState extends State<CatalogStartTiles> {
  static const _tabs = [
    (ContentType.live, 'Diretta', Icons.live_tv_rounded),
    (ContentType.movie, 'Film', Icons.movie_rounded),
    (ContentType.series, 'Serie TV', Icons.video_library_rounded),
  ];
  final Map<ContentType, CatalogStartCategory> _values = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final (type, _, _) in _tabs) {
      final value = await CatalogViewMemory.startCategory(type);
      if (!mounted) return;
      setState(() => _values[type] = value);
    }
  }

  String _label(CatalogStartCategory value, ContentType type) =>
      value.kind == CatalogStartKind.group && value.group == null
      ? 'Una categoria…'
      : value.label(type);

  Future<void> _pick(ContentType type, String tab) async {
    final current = _values[type] ?? CatalogStartCategory.defaultFor(type);
    final picked = await pickOption<CatalogStartCategory>(
      context,
      title: 'Apri $tab su',
      options: [
        for (final kind in CatalogStartCategory.kindsFor(type))
          kind == CatalogStartKind.group
              ? (current.kind == kind
                    ? current
                    : const CatalogStartCategory(CatalogStartKind.group))
              : CatalogStartCategory(kind),
      ],
      current: current,
      label: (v) => _label(v, type),
      detail: (v) => switch (v.kind) {
        CatalogStartKind.last => 'Dove l\'hai lasciata l\'ultima volta',
        CatalogStartKind.group => 'Scegli una categoria della sorgente',
        _ => null,
      },
    );
    if (picked == null || !mounted) return;
    var value = picked;
    if (picked.kind == CatalogStartKind.group) {
      final group = await _pickGroup(type, tab, current.group);
      if (group == null || !mounted) return;
      value = CatalogStartCategory(CatalogStartKind.group, group);
    }
    await CatalogViewMemory.saveStartCategory(type, value);
    if (mounted) setState(() => _values[type] = value);
  }

  Future<String?> _pickGroup(ContentType type, String tab, String? current) {
    final labels = [
      for (final g in context.read<AppProvider>().groupedCatalog(type))
        if (g.entries.isNotEmpty) g.label,
    ];
    if (labels.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Nessuna categoria disponibile in $tab')),
      );
      return Future.value();
    }
    return pickOption<String>(
      context,
      title: 'Categoria iniziale · $tab',
      options: labels,
      current: labels.contains(current) ? current! : labels.first,
      label: (l) => l,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (type, tab, icon) in _tabs)
        SettingsValueTile(
          icon: icon,
          title: 'Apri $tab su',
          value: _values[type] == null ? null : _label(_values[type]!, type),
          onTap: () => _pick(type, tab),
        ),
    ],
  );
}
