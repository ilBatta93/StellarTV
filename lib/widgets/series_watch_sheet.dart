import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/series_details.dart';
import '../providers/history_provider.dart';
import '../widgets/tv_focusable.dart';

class SeriesWatchSheet extends StatefulWidget {
  final SeriesDetails details;
  const SeriesWatchSheet({super.key, required this.details});
  @override
  State<SeriesWatchSheet> createState() => _SeriesWatchSheetState();
}

class _SeriesWatchSheetState extends State<SeriesWatchSheet> {
  SeriesSeason? selected;
  bool busy = false;

  Future<void> apply(Iterable<SeriesEpisode> episodes, bool? value) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await context.read<HistoryProvider>().setManualWatched(
        episodes.map((e) => e.channel.id),
        value,
        seriesId: widget.details.series.seriesKey ?? widget.details.series.id,
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salvataggio non riuscito. Riprova.')),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget row(String title, String subtitle, IconData icon, VoidCallback run) =>
      TvFocusable(
        focusedScale: 1,
        onPressed: () {
          if (!busy) run();
        },
        child: ListTile(
          enabled: !busy,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy ? null : run,
        ),
      );

  Future<void> choose(String title, List<SeriesEpisode> episodes) async {
    if (busy) return;
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in const [
                (1, 'Visto', Icons.check_circle_outline),
                (0, 'Non visto', Icons.radio_button_unchecked),
                (3, 'Automatico dal progresso', Icons.restore),
              ])
                TvFocusable(
                  focusedScale: 1,
                  onPressed: () => Navigator.pop(ctx, option.$1),
                  child: ListTile(
                    title: Text(option.$2),
                    leading: Icon(option.$3),
                    onTap: () => Navigator.pop(ctx, option.$1),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    await apply(episodes, choice == 3 ? null : choice == 1);
  }

  String status(HistoryProvider history, String id) {
    final manual = history.manualWatched(id);
    if (manual == true) return 'Visto · manuale';
    if (manual == false) return 'Non visto · manuale';
    final entry = history.entryFor(id);
    if (history.isWatched(id)) return 'Visto · automatico';
    if (entry == null || entry.position == Duration.zero)
      return 'Non iniziato · automatico';
    return 'In corso · ${(entry.progress * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final season = selected;
    final all = widget.details.allEpisodes;
    return PopScope(
      canPop: season == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && season != null) setState(() => selected = null);
      },
      child: AlertDialog(
        title: Text(season == null ? 'Gestisci visione' : season.name),
        content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: ListView(
            children: [
              if (busy) const LinearProgressIndicator(),
              if (season == null) ...[
                row(
                  'Intera raccolta',
                  '${all.where((e) => history.isWatched(e.channel.id)).length} di ${all.length} episodi visti',
                  Icons.done_all,
                  () => choose('Intera raccolta', all),
                ),
                const Divider(),
                for (final s in widget.details.seasons)
                  row(
                    s.name,
                    '${s.episodes.where((e) => history.isWatched(e.channel.id)).length} di ${s.episodes.length} visti',
                    Icons.list,
                    () => setState(() => selected = s),
                  ),
              ] else ...[
                row(
                  'Tutta la stagione',
                  '${season.episodes.where((e) => history.isWatched(e.channel.id)).length} di ${season.episodes.length} visti',
                  Icons.done_all,
                  () => choose(season.name, season.episodes),
                ),
                if (widget.details.seasons.any(
                  (s) => s.number > 0 && s.number < season.number,
                ))
                  row(
                    'Stagioni precedenti',
                    'Solo quelle precedenti alla ${season.number}',
                    Icons.history,
                    () => choose(
                      'Stagioni precedenti',
                      widget.details.seasons
                          .where(
                            (s) => s.number > 0 && s.number < season.number,
                          )
                          .expand((s) => s.episodes)
                          .toList(),
                    ),
                  ),
                const Divider(),
                for (final e in season.episodes)
                  row(
                    '${e.code} · ${e.title}',
                    status(history, e.channel.id),
                    Icons.playlist_add_check,
                    () => choose(e.code, [e]),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () {
              if (season == null)
                Navigator.pop(context);
              else
                setState(() => selected = null);
            },
            child: Text(season == null ? 'Chiudi' : 'Stagioni'),
          ),
        ],
      ),
    );
  }
}
