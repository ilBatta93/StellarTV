import 'package:flutter/material.dart';

import '../widgets/apple_page_scaffold.dart';

import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';

/// History filter shown above the list.
enum HistoryFilter { all, movies, series }

/// Pure split used by the history screen; live entries only appear in "Tutti".
List<HistoryEntry> filterHistory(List<HistoryEntry> e, HistoryFilter f) =>
    switch (f) {
      HistoryFilter.all => e,
      HistoryFilter.movies =>
        e.where((x) => x.type == ContentType.movie).toList(),
      HistoryFilter.series =>
        e
            .where(
              (x) =>
                  x.type == ContentType.series || x.type == ContentType.anime,
            )
            .toList(),
    };

class HistorySettingsScreen extends StatefulWidget {
  const HistorySettingsScreen({super.key});

  @override
  State<HistorySettingsScreen> createState() => _HistorySettingsScreenState();
}

class _HistorySettingsScreenState extends State<HistorySettingsScreen> {
  HistoryFilter _filter = HistoryFilter.all;

  Widget _filters(List<HistoryEntry> all) {
    Widget chip(HistoryFilter f, String label) {
      final n = filterHistory(all, f).length;
      final on = _filter == f;
      void pick() => setState(() => _filter = f);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TvFocusable(
          focusedScale: 1,
          autofocus: f == HistoryFilter.all && DeviceTypeService.isTv,
          borderRadius: BorderRadius.circular(18),
          onPressed: pick,
          child: GestureDetector(
            onTap: pick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: on
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: on ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                '$label · $n',
                style: TextStyle(
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(HistoryFilter.all, 'Tutti'),
        chip(HistoryFilter.movies, 'Film'),
        chip(HistoryFilter.series, 'Serie TV'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final app = context.watch<AppProvider>();
    final entries = history.entriesOnePerSeries
        .where(
          (e) =>
              !app.kidsMode ||
              app.isKidsContent(
                app.channelById(e.contentId) ??
                    Channel(
                      id: e.contentId,
                      name: e.title,
                      url: e.url,
                      logo: e.posterUrl,
                      group: e.group,
                      type: e.type,
                      seriesName: e.seriesName.isEmpty ? null : e.seriesName,
                    ),
              ),
        )
        .toList();

    if (!history.hasLoaded && history.isLoading) {
      return ApplePageScaffold(
        title: 'Cronologia',
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (entries.isEmpty) {
      final failed = history.error != null;
      return ApplePageScaffold(
        title: 'Cronologia',
        body: RefreshIndicator(
          onRefresh: history.refresh,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: constraints.maxHeight,
                child: EmptyState(
                  icon: failed
                      ? Icons.cloud_off_rounded
                      : Icons.history_rounded,
                  title: failed
                      ? 'Impossibile caricare la cronologia'
                      : 'Nessuna visione recente',
                  message: failed
                      ? 'Controlla la connessione e riprova.'
                      : 'I contenuti che avvii appariranno qui.',
                  action: failed
                      ? OutlinedButton.icon(
                          onPressed: history.refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Riprova'),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final shown = filterHistory(entries, _filter);
    return ApplePageScaffold(
      title: 'Cronologia',
      body: RefreshIndicator(
        onRefresh: history.refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: shown.length + 2,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == 0) return _Header(count: entries.length);
            if (i == 1) {
              if (shown.isNotEmpty) return _filters(entries);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _filters(entries),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Nessun contenuto in questa categoria.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              );
            }
            final entry = shown[i - 2];
            final isSeries =
                entry.type == ContentType.series ||
                entry.type == ContentType.anime;
            if (!isSeries) {
              return _HistoryTile(key: ValueKey(entry.contentId), entry: entry);
            }
            return _SeriesGroup(
              key: ValueKey('series-${entry.contentId}'),
              entry: entry,
              episodes: history.episodesOfSeries(entry),
            );
          },
        ),
      ),
    );
  }
}

void _showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Svuotare la cronologia?'),
        content: const Text(
          'Tutti i contenuti visti e le posizioni di riproduzione salvate verranno eliminati da tutti i tuoi dispositivi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Svuota'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await context.read<HistoryProvider>().clear();
    if (!context.mounted) return;
    _showMessage(
      context,
      ok ? 'Cronologia svuotata' : 'Impossibile svuotare la cronologia',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cronologia',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                count == 1 ? '1 contenuto' : '$count contenuti',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
          label: const Text('Svuota'),
          onPressed: () => _confirmClear(context),
        ),
      ],
    );
  }
}

/// One series row (removes the whole series) with an expandable list of its
/// watched episodes, each removable on its own.
class _SeriesGroup extends StatefulWidget {
  final HistoryEntry entry;
  final List<HistoryEntry> episodes;
  const _SeriesGroup({super.key, required this.entry, required this.episodes});

  @override
  State<_SeriesGroup> createState() => _SeriesGroupState();
}

class _SeriesGroupState extends State<_SeriesGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final name = e.seriesName.isNotEmpty ? e.seriesName : e.title;
    final n = widget.episodes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HistoryTile(
          entry: e,
          titleOverride: name,
          series: true,
          episodesOpen: _open,
          onToggleEpisodes: () => setState(() => _open = !_open),
        ),
        if (!DeviceTypeService.isTv)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                ),
                label: Text(
                  _open
                      ? 'Nascondi episodi'
                      : n == 1
                      ? 'Mostra 1 episodio'
                      : 'Mostra $n episodi',
                ),
              ),
            ),
          ),
        if (_open)
          for (final ep in widget.episodes)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 8),
              child: _HistoryTile(
                key: ValueKey('ep-${ep.contentId}'),
                entry: ep,
                episodeOnly: true,
              ),
            ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final String? titleOverride;
  final bool series;
  final bool episodeOnly;
  final bool episodesOpen;
  final VoidCallback? onToggleEpisodes;
  const _HistoryTile({
    this.episodesOpen = false,
    this.onToggleEpisodes,
    super.key,
    required this.entry,
    this.titleOverride,
    this.series = false,
    this.episodeOnly = false,
  });

  static String _typeLabel(ContentType t) {
    switch (t) {
      case ContentType.live:
        return 'Diretta';
      case ContentType.movie:
        return 'Film';
      case ContentType.series:
        return 'Serie TV';
      case ContentType.anime:
        return 'Anime';
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _when(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    final time = '${_two(local.hour)}:${_two(local.minute)}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    if (days == 0) return 'Oggi, $time';
    if (days == 1) return 'Ieri, $time';
    return '${_two(local.day)}/${_two(local.month)}/${local.year}, $time';
  }

  static String _remaining(HistoryEntry e) {
    final left = e.duration - e.position;
    if (left.inMinutes < 1) return 'Completato';
    if (left.inHours > 0) {
      return 'Mancano ${left.inHours} h ${left.inMinutes.remainder(60)} min';
    }
    return 'Mancano ${left.inMinutes} min';
  }

  void _open(BuildContext context) {
    final app = context.read<AppProvider>();
    var channel = app.channelById(entry.contentId);
    if (channel == null && entry.url.isNotEmpty) {
      // Rebuilt from the stored stream URL when the playlist has changed
      // and the channel is no longer present in it.
      channel = Channel(
        id: entry.contentId,
        name: entry.title,
        url: entry.url,
        logo: entry.posterUrl,
        group: entry.group,
        type: entry.type,
      );
    }
    if (channel == null) {
      _showMessage(
        context,
        'Contenuto non disponibile nella configurazione attuale',
      );
      return;
    }
    if (channel.type == ContentType.series ||
        channel.type == ContentType.anime) {
      openChannel(context, channel);
    } else {
      playChannel(context, channel, startAt: entry.resumePosition);
    }
  }

  Future<void> _remove(BuildContext context) async {
    final history = context.read<HistoryProvider>();
    final ok = series
        ? await history.removeSeries(entry)
        : await history.remove(entry.contentId, cascade: !episodeOnly);
    if (!ok && context.mounted) {
      _showMessage(context, 'Impossibile rimuovere "${entry.title}"');
    }
  }

  /// TV: long-press OK opens the actions, so each row is one D-Pad stop.
  Future<void> _actions(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(titleOverride ?? entry.title),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'open'),
            child: const Text('Apri'),
          ),
          if (onToggleEpisodes != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'toggle'),
              child: Text(episodesOpen ? 'Nascondi episodi' : 'Mostra episodi'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: Text(
              series
                  ? 'Rimuovi serie dalla cronologia'
                  : episodeOnly
                  ? 'Rimuovi episodio'
                  : 'Rimuovi dalla cronologia',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'open') _open(context);
    if (choice == 'toggle') onToggleEpisodes?.call();
    if (choice == 'remove') await _remove(context);
  }

  @override
  Widget build(BuildContext context) {
    final isLive = entry.isLive;
    final progress = entry.progress;
    final subtitle = [
      if (episodeOnly) 'Episodio' else _typeLabel(entry.type),
      if (series)
        'Ultimo: ${entry.title}'
      else if (!episodeOnly && entry.group.isNotEmpty)
        entry.group,
      if (DeviceTypeService.isTv && series)
        episodesOpen
            ? 'Tieni premuto OK: opzioni'
            : 'Tieni premuto OK: episodi e opzioni',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(
        'dismiss-${series
            ? 's'
            : episodeOnly
            ? 'e'
            : 'x'}-${entry.contentId}',
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _remove(context),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text(
              'Rimuovi',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TvFocusable(
              onPressed: () => _open(context),
              onLongPress: () => _actions(context),
              focusedScale: 1,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(context),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            color: AppColors.card,
                            width: isLive ? 96 : 56,
                            height: 80,
                            child: PosterImage(
                              url: series && entry.seriesPoster.isNotEmpty
                                  ? entry.seriesPoster
                                  : entry.posterUrl,
                              fit: isLive ? BoxFit.contain : BoxFit.cover,
                              fallbackIcon: isLive
                                  ? Icons.live_tv_rounded
                                  : Icons.movie_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleOverride ?? entry.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _when(entry.lastWatchedAt),
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              if (progress != null) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3,
                                    backgroundColor: AppColors.border,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _remaining(entry),
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!DeviceTypeService.isTv)
                          IconButton(
                            tooltip: series
                                ? 'Rimuovi serie dalla cronologia'
                                : episodeOnly
                                ? 'Rimuovi episodio'
                                : 'Rimuovi dalla cronologia',
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => _remove(context),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
