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
      await context.read<HistoryProvider>().setManualWatched(episodes.map((e) => e.channel.id), value, seriesId: widget.details.series.seriesKey ?? widget.details.series.id);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salvataggio non riuscito. Riprova.')));
    } finally { if (mounted) setState(() => busy = false); }
  }
  Widget action(String label, IconData icon, VoidCallback run, {bool autofocus = false}) => TvFocusable(
    autofocus: autofocus, onPressed: () { if (!busy) run(); },
    child: OutlinedButton.icon(onPressed: busy ? null : run, icon: Icon(icon), label: Text(label)),
  );
  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final season = selected;
    final all = widget.details.allEpisodes;
    return PopScope(
      canPop: season == null,
      onPopInvokedWithResult: (didPop, _) { if (!didPop && season != null) setState(() => selected = null); },
      child: AlertDialog(
        title: Text(season == null ? 'Gestisci visione' : season.name),
        content: SizedBox(width: 640, height: MediaQuery.sizeOf(context).height * 0.55,
          child: ListView(children: [
            if (busy) const LinearProgressIndicator(),
            if (season == null) ...[
              Text('${all.where((e) => history.isWatched(e.channel.id)).length} di ${all.length} episodi visti'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                action('Segna tutta la serie', Icons.done_all, () => apply(all, true)),
                action('Segna tutta non vista', Icons.remove_done, () => apply(all, false)),
                action('Usa progressi reali', Icons.restore, () => apply(all, null)),
              ]),
              const SizedBox(height: 20),
              for (final s in widget.details.seasons) Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.name} · ${s.episodes.where((e) => history.isWatched(e.channel.id)).length}/${s.episodes.length}'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  action('Episodi', Icons.list, () => setState(() => selected = s)),
                  action('Vista', Icons.check, () => apply(s.episodes, true)),
                  action('Non vista', Icons.undo, () => apply(s.episodes, false)),
                  if (widget.details.seasons.any((previous) => previous.number > 0 && previous.number < s.number))
                    action('Segna le precedenti', Icons.done_all, () => apply(widget.details.seasons.where((previous) => previous.number > 0 && previous.number < s.number).expand((previous) => previous.episodes), true)),
                ]),
              ])),
            ] else ...[
              for (final e in season.episodes) Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e.code} · ${e.title}'),
                Text(history.manualWatched(e.channel.id) == true ? 'Completato manualmente' : history.manualWatched(e.channel.id) == false ? 'Non visto · scelta manuale' : history.isWatched(e.channel.id) ? 'Completato automaticamente' : (history.entryFor(e.channel.id)?.position ?? Duration.zero) > Duration.zero ? 'In corso' : 'Non iniziato'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  action(history.isWatched(e.channel.id) ? 'Segna non visto' : 'Segna visto', Icons.check_circle_outline, () => apply([e], !history.isWatched(e.channel.id))),
                  action('Usa progresso reale', Icons.restore, () => apply([e], null)),
                ]),
              ])),
            ],
          ])),
        actions: [action(season == null ? 'Chiudi' : 'Stagioni', Icons.arrow_back, () { if (season == null) Navigator.pop(context); else setState(() => selected = null); }, autofocus: true)],
      ),
    );
  }
}