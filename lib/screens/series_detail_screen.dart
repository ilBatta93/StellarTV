import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/series_details.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';

class SeriesDetailScreen extends StatefulWidget {
  final Channel series;

  const SeriesDetailScreen({super.key, required this.series});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  SeriesDetails? _details;
  bool _loading = true;
  String? _error;
  int _selectedSeason = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details =
          await context.read<AppProvider>().loadSeriesDetails(widget.series);
      if (!mounted) return;
      setState(() {
        _details = details;
        _selectedSeason = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile caricare episodi e stagioni.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = _details?.series ?? widget.series;
    final seasons = _details?.seasons ?? const [];
    final currentSeason =
        seasons.isNotEmpty && _selectedSeason < seasons.length
            ? seasons[_selectedSeason]
            : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: AppColors.background,
            leading: const BackButton(),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: series.logo),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x8009090D),
                          Colors.transparent,
                          AppColors.background
                        ],
                        stops: [0, 0.4, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(series.displaySeriesName,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(label: 'Serie TV'),
                      if (seasons.isNotEmpty)
                        _Chip(label: '${seasons.length} stagioni'),
                      if (series.episodeCount > 0)
                        _Chip(label: '${series.episodeCount} episodi'),
                      _Chip(label: series.group),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (series.plot != null && series.plot!.trim().isNotEmpty) ...[
                    Text('Trama', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(series.plot!,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: _error!,
                message: 'Controlla la connessione e riprova.',
                action: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Riprova'),
                  onPressed: _load,
                ),
              ),
            )
          else if (currentSeason == null)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.tv_off_rounded,
                title: 'Nessun episodio',
                message: 'Questa serie non ha episodi disponibili.',
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final selected = i == _selectedSeason;
                    return ChoiceChip(
                      label: Text(seasons[i].name),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedSeason = i),
                      labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                          color:
                              selected ? AppColors.primary : AppColors.border),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
            ),
            SliverList.builder(
              itemCount: currentSeason.episodes.length,
              itemBuilder: (context, i) {
                final ep = currentSeason.episodes[i];
                return _EpisodeTile(
                  episode: ep,
                  onTap: () => playChannel(context, ep.channel),
                );
              },
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final SeriesEpisode episode;
  final VoidCallback onTap;

  const _EpisodeTile({required this.episode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ep = episode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 120,
                    height: 68,
                    child: ep.image != null && ep.image!.isNotEmpty
                        ? Image.network(
                            ep.image!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ep.code} · ${ep.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (ep.overview != null &&
                          ep.overview!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          ep.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (ep.duration != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(ep.duration!),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_circle_fill_rounded,
                    color: AppColors.primary, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surface,
        child: const Icon(Icons.movie_outlined,
            color: AppColors.textMuted, size: 28),
      );

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '$h ore $m min' : '$m min';
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }
}
