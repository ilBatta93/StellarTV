import 'package:flutter/material.dart';
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

class HistorySettingsScreen extends StatelessWidget {
  const HistorySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();

    if (!history.hasLoaded && history.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cronologia')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (history.entries.isEmpty) {
      final failed = history.error != null;
      return Scaffold(
        appBar: AppBar(title: const Text('Cronologia')),
        body: RefreshIndicator(
          onRefresh: history.refresh,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: constraints.maxHeight,
                child: EmptyState(
                  icon: failed ? Icons.cloud_off_rounded : Icons.history_rounded,
                  title: failed
                      ? 'Impossibile caricare la cronologia'
                      : 'Nessuna visione recente',
                  message: failed
                      ? 'Controlla la connessione e riprova.'
                      : 'I canali, i film e le serie che avvii appariranno qui.',
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

    final entries = history.entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Cronologia')),
      body: RefreshIndicator(
        onRefresh: history.refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: entries.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == 0) return _Header(count: entries.length);
            final entry = entries[i - 1];
            return _HistoryTile(key: ValueKey(entry.contentId), entry: entry);
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
            'Tutti i contenuti visti e le posizioni di riproduzione salvate verranno eliminati da tutti i tuoi dispositivi.'),
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
    _showMessage(context,
        ok ? 'Cronologia svuotata' : 'Impossibile svuotare la cronologia');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cronologia',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                count == 1 ? '1 contenuto' : '$count contenuti',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
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

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryTile({super.key, required this.entry});

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
      _showMessage(context, 'Contenuto non disponibile nella playlist attuale');
      return;
    }
    if (channel.type == ContentType.series || channel.type == ContentType.anime) {
      openChannel(context, channel);
    } else {
      playChannel(context, channel, startAt: entry.resumePosition);
    }
  }

  Future<void> _remove(BuildContext context) async {
    final ok = await context.read<HistoryProvider>().remove(entry.contentId);
    if (!ok && context.mounted) {
      _showMessage(context, 'Impossibile rimuovere "${entry.title}"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLive = entry.isLive;
    final progress = entry.progress;
    final subtitle = [
      _typeLabel(entry.type),
      if (entry.group.isNotEmpty) entry.group,
    ].join(' · ');

    return Dismissible(
      key: ValueKey('dismiss-${entry.contentId}'),
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
            Text('Rimuovi',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Row(
          children: [
            Expanded(
              child: TvFocusable(
                onPressed: () => _open(context),
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
                                url: entry.posterUrl,
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
                                Text(entry.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2)),
                                const SizedBox(height: 4),
                                Text(subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.schedule_rounded,
                                      size: 13, color: AppColors.textMuted),
                                  const SizedBox(width: 4),
                                  Text(_when(entry.lastWatchedAt),
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                                ]),
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
                                  Text(_remaining(entry),
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11)),
                                ],
                              ],
                            ),
                          ),
                          if (!DeviceTypeService.isTv)
                            IconButton(
                              tooltip: 'Rimuovi dalla cronologia',
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.textSecondary),
                              onPressed: () => _remove(context),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (DeviceTypeService.isTv) ...[
              const SizedBox(width: 8),
              TvFocusable(
                onPressed: () => _remove(context),
                borderRadius: BorderRadius.circular(24),
                child: IconButton(
                  tooltip: 'Rimuovi dalla cronologia',
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                  onPressed: () => _remove(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
