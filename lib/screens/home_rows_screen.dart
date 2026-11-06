import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/home_layout_preferences.dart';
import '../models/streaming_platform.dart';
import '../providers/ui_settings.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/tv_focusable.dart';

/// Home rows in the user's order, hidden ones included.
List<String> homeRowsOrder(UiSettings ui) => HomeRows.arrange(
  HomeRows.defaults(
    tv: DeviceTypeService.isTv,
    platforms: StreamingPlatform.all.map((p) => p.name),
  ),
  ui.homeRowOrder,
);

String homeRowLabel(String id) {
  switch (id) {
    case HomeRows.recentSeries:
      return 'Serie viste di recente';
    case HomeRows.recentMovies:
      return 'Film visti di recente';
    case HomeRows.forYouMovies:
      return 'Film consigliati per te';
    case HomeRows.forYouSeries:
      return 'Serie consigliate per te';
    case HomeRows.topWeek:
      return 'Top 10 della settimana';
    case HomeRows.awards:
      return 'Oscar ed Emmy';
  }
  for (final p in StreamingPlatform.all) {
    if (HomeRows.top(p.name) == id) return 'Top 10 su ${p.name}';
  }
  return id;
}

IconData _rowIcon(String id) => switch (id) {
  HomeRows.recentSeries || HomeRows.recentMovies => Icons.history_rounded,
  HomeRows.forYouMovies || HomeRows.forYouSeries => Icons.auto_awesome_rounded,
  HomeRows.topWeek => Icons.trending_up_rounded,
  _ => Icons.emoji_events_outlined,
};

/// Short summary for the settings tile: "12 di 14 visibili".
String homeRowsSummary(UiSettings ui) {
  final order = homeRowsOrder(ui);
  final visible = HomeRows.visible(order, ui.homeHiddenRows).length;
  return visible == order.length ? 'Tutte' : '$visible di ${order.length}';
}

class HomeRowsScreen extends StatefulWidget {
  const HomeRowsScreen({super.key});

  @override
  State<HomeRowsScreen> createState() => _HomeRowsScreenState();
}

class _HomeRowsScreenState extends State<HomeRowsScreen> {
  final Map<String, FocusNode> _moveNodes = {};
  String? _moving;

  FocusNode _moveNode(String id) =>
      _moveNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'row-move-$id'));

  @override
  void dispose() {
    for (final n in _moveNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _move(UiSettings ui, String id, int delta) async {
    final order = homeRowsOrder(ui);
    final from = order.indexOf(id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= order.length) return;
    order.insert(to, order.removeAt(from));
    await ui.setHomeRowOrder(order);
    if (!DeviceTypeService.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _moveNodes[id]?.requestFocus();
    });
  }

  KeyEventResult _onMoveKey(UiSettings ui, String id, KeyEvent event) {
    if (_moving != id || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(ui, id, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(ui, id, 1);
      return KeyEventResult.handled;
    }
    // Left/right are blocked while moving so the focus stays on the row.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _reset(UiSettings ui) async {
    setState(() => _moving = null);
    await ui.resetHomeRows();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    final order = homeRowsOrder(ui);
    final tv = DeviceTypeService.isTv;
    return PopScope(
      canPop: _moving == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _moving != null) setState(() => _moving = null);
      },
      child: ApplePageScaffold(
        title: 'Righe della Home',
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              tv
                  ? 'OK mostra o nasconde una riga. Per spostarla vai su '
                        '«Sposta», premi OK, usa Su/Giù e premi di nuovo OK.'
                  : 'Accendi le righe da vedere in Home e riordinale con '
                        'le frecce. Le righe senza titoli restano nascoste.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < order.length; i++)
              Padding(
                key: ValueKey(order[i]),
                padding: const EdgeInsets.only(bottom: 8),
                child: tv ? _tvRow(ui, order, i) : _touchRow(ui, order, i),
              ),
            const SizedBox(height: 8),
            TvFocusable(
              focusedScale: 1,
              borderRadius: BorderRadius.circular(12),
              onPressed: () => _reset(ui),
              child: OutlinedButton.icon(
                onPressed: () => _reset(ui),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Ripristina righe predefinite'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _touchRow(UiSettings ui, List<String> order, int index) {
    final id = order[index];
    final visible = !ui.homeHiddenRows.contains(id);
    return Card(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              secondary: Icon(_rowIcon(id), color: AppColors.primary),
              title: Text(homeRowLabel(id)),
              value: visible,
              onChanged: (v) => ui.setHomeRowVisible(id, v),
            ),
          ),
          IconButton(
            tooltip: 'Sposta su',
            onPressed: index == 0 ? null : () => _move(ui, id, -1),
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: 'Sposta giù',
            onPressed: index == order.length - 1
                ? null
                : () => _move(ui, id, 1),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
        ],
      ),
    );
  }

  Widget _tvRow(UiSettings ui, List<String> order, int index) {
    final id = order[index];
    final visible = !ui.homeHiddenRows.contains(id);
    final moving = _moving == id;
    return Row(
      children: [
        Expanded(
          child: TvFocusable(
            autofocus: index == 0,
            focusedScale: 1,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => ui.setHomeRowVisible(id, !visible),
            child: Container(
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
                  Icon(
                    _rowIcon(id),
                    color: visible ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      homeRowLabel(id),
                      style: TextStyle(
                        color: visible
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    visible ? 'Visibile' : 'Nascosta',
                    style: TextStyle(
                      color: visible ? AppColors.primary : AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    visible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: visible ? AppColors.primary : AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, e) => _onMoveKey(ui, id, e),
          child: TvFocusable(
            focusNode: _moveNode(id),
            focusedScale: 1,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => setState(() => _moving = moving ? null : id),
            child: Container(
              width: 170,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: moving
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    moving
                        ? Icons.swap_vert_rounded
                        : Icons.drag_indicator_rounded,
                    color: moving ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      moving ? 'Su/Giù · OK' : 'Sposta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: moving ? AppColors.primary : AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
