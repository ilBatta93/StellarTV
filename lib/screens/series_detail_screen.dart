import '../services/image_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/series_details.dart';
import '../models/tmdb_item.dart';
import '../models/tmdb_person.dart';
import '../providers/discover_provider.dart';
import '../providers/history_provider.dart';
import '../widgets/cast_row.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_detail_backdrop.dart';
import '../widgets/download_button.dart';

class SeriesDetailScreen extends StatefulWidget {
  final Channel series;

  /// TMDB info when already known (e.g. opened from the Top 10).
  final TmdbItem? item;

  const SeriesDetailScreen({super.key, required this.series, this.item});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  SeriesDetails? _details;
  bool _loading = true;
  String? _error;
  int _selectedSeason = 0;
  TmdbItem? _item;
  List<TmdbPerson> _cast = [];
  List<TmdbItem> _similar = [];

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _load();
    _loadInfo();
  }

  /// Plot, backdrop and cast from TMDB, loaded alongside the episodes.
  Future<void> _loadInfo() async {
    try {
      final tmdb = context.read<DiscoverProvider>().tmdb;
      final item =
          _item ??
          await tmdb.findByTitle(
            widget.series.displaySeriesName,
            isMovie: false,
          );
      if (item == null) return;
      final cast = await tmdb.cast(item);
      final recommendations = await tmdb.recommendations(item);
      if (!mounted) return;
      final app = context.read<AppProvider>();
      setState(() {
        _item = item;
        _cast = cast.take(20).toList();
        _similar = recommendations
            .where((candidate) => app.findChannelFor(candidate) != null)
            .take(20)
            .toList();
      });
    } catch (_) {
      // Info is optional: seasons and episodes still work without it.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await context.read<AppProvider>().loadSeriesDetails(
        widget.series,
      );
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
    final app = context.watch<AppProvider>();
    final isFav = app.favoriteIds.contains(widget.series.id);
    final item = _item;
    final plot = (series.plot != null && series.plot!.trim().isNotEmpty)
        ? series.plot!
        : (item?.overview ?? '');
    final image = item?.backdropUrl ?? series.logo;
    final seasons = _details?.seasons ?? const [];
    final currentSeason = seasons.isNotEmpty && _selectedSeason < seasons.length
        ? seasons[_selectedSeason]
        : null;

    final scroll = CustomScrollView(
      // TV: every section stays built, so going up always reaches the
      // title and the buttons at the top of the page.
      cacheExtent: DeviceTypeService.isTv ? 1200 : null,
      slivers: [
        if (DeviceTypeService.isTv)
          SliverToBoxAdapter(
            child: SizedBox(height: TvDetailBackdrop.topSpace(context)),
          )
        else
          SliverAppBar(
            pinned: !DeviceTypeService.isTv,
            automaticallyImplyLeading: !DeviceTypeService.isTv,
            expandedHeight: DeviceTypeService.isTv ? 180 : 280,
            backgroundColor: AppColors.background,
            leading: DeviceTypeService.isTv ? null : const BackButton(),
            actions: [
              if (!DeviceTypeService.isTv)
                IconButton(
                  tooltip: 'Preferiti',
                  icon: Icon(
                    isFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFav ? AppColors.primary : AppColors.textPrimary,
                  ),
                  onPressed: () => app.toggleFavorite(widget.series),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: image),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x8009090D),
                          Colors.transparent,
                          AppColors.background,
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
                Text(
                  series.displaySeriesName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
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
                if (DeviceTypeService.isTv) ...[
                  _buildTvActions(context, isFav),
                  const SizedBox(height: 16),
                ],
                if (plot.trim().isNotEmpty) ...[
                  Text('Trama', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(plot, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: CastRow(cast: _cast)),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'Stagioni ed episodi',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
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
                  return TvFocusable(
                    onPressed: () => setState(() => _selectedSeason = i),
                    child: ChoiceChip(
                      label: Text(seasons[i].name),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedSeason = i),
                      labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                        color: selected ? AppColors.primary : AppColors.border,
                      ),
                      showCheckmark: false,
                    ),
                  );
                },
              ),
            ),
          ),
          SliverList.builder(
            itemCount: currentSeason.episodes.length,
            itemBuilder: (context, i) {
              final ep = currentSeason.episodes[i];
              final history = context.watch<HistoryProvider>();
              final entry = history.entryFor(ep.channel.id);
              return _EpisodeTile(
                episode: ep,
                progress: entry?.isWatched == true ? null : entry?.progress,
                watched: entry?.isWatched ?? false,
                onToggleWatched: () {
                  final h = context.read<HistoryProvider>();
                  if (entry?.isWatched ?? false) {
                    h.markUnwatched(ep.channel.id);
                  } else {
                    h.markWatched(ep.channel, duration: ep.duration);
                  }
                },
                onTap: () => playChannel(
                  context,
                  ep.channel,
                  queue: [
                    for (final e in _details?.allEpisodes ?? const [])
                      e.channel,
                  ],
                  startAt: context
                      .read<HistoryProvider>()
                      .entryFor(ep.channel.id)
                      ?.resumePosition,
                ),
              );
            },
          ),
        ],
        if (_similar.isNotEmpty)
          SliverToBoxAdapter(child: _buildSimilar(context)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
    if (DeviceTypeService.isTv) {
      return TvDetailBackdrop(image: image, child: scroll);
    }
    return Scaffold(body: scroll);
  }

  /// Episode to start from: the one in progress, otherwise the first one
  /// after the last watched episode.
  SeriesEpisode? _resumeEpisode(HistoryProvider history) {
    final all = _details?.allEpisodes ?? const <SeriesEpisode>[];
    if (all.isEmpty) return null;
    var lastWatched = -1;
    for (final (i, e) in all.indexed) {
      final entry = history.entryFor(e.channel.id);
      if (entry == null) continue;
      if (entry.isWatched) {
        lastWatched = i;
      } else if ((entry.resumePosition ?? Duration.zero) > Duration.zero) {
        return e;
      }
    }
    return lastWatched + 1 < all.length ? all[lastWatched + 1] : all.first;
  }

  /// TV only: focusable buttons at the top of the page (first focus).
  Widget _buildTvActions(BuildContext context, bool isFav) {
    final history = context.watch<HistoryProvider>();
    final app = context.read<AppProvider>();
    final episode = _resumeEpisode(history);
    final started =
        episode != null && history.entryFor(episode.channel.id) != null;
    void play() {
      if (episode == null) return;
      playChannel(
        context,
        episode.channel,
        queue: [for (final e in _details?.allEpisodes ?? const []) e.channel],
        startAt: history.entryFor(episode.channel.id)?.resumePosition,
      );
    }

    return Row(
      children: [
        TvFocusable(
          autofocus: true,
          onPressed: play,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              episode == null
                  ? (_loading ? 'Caricamento episodi...' : 'Guarda ora')
                  : '${started ? 'Riprendi' : 'Guarda'} ${episode.code}',
            ),
            onPressed: play,
          ),
        ),
        const SizedBox(width: 12),
        TvFocusable(
          onPressed: () => app.toggleFavorite(widget.series),
          child: OutlinedButton.icon(
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppColors.primary : AppColors.textPrimary,
            ),
            label: Text(isFav ? 'Nei preferiti' : 'Aggiungi ai preferiti'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
            ),
            onPressed: () => app.toggleFavorite(widget.series),
          ),
        ),
      ],
    );
  }

  Widget _buildSimilar(BuildContext context) {
    final similar = _similar
        .where(context.watch<AppProvider>().isTmdbAllowed)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Titoli simili',
          subtitle: 'Disponibili nella tua playlist',
        ),
        HorizontalRow(
          height: tmdbPosterRowHeight(context),
          itemCount: similar.length,
          itemBuilder: (context, index) {
            final item = similar[index];
            return TmdbPosterCard(
              item: item,
              onTap: () => openTmdbItem(context, item),
            );
          },
        ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final SeriesEpisode episode;
  final VoidCallback onTap;
  final double? progress;
  final bool watched;
  final VoidCallback onToggleWatched;

  const _EpisodeTile({
    required this.episode,
    required this.onTap,
    required this.onToggleWatched,
    this.progress,
    this.watched = false,
  });

  @override
  Widget build(BuildContext context) {
    final ep = episode;
    final card = Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onToggleWatched,
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
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ep.image != null && ep.image!.isNotEmpty
                          ? CachedNetworkImage(
                              cacheManager: AppImageCache.manager,
                              imageUrl: ep.image!,
                              fadeInDuration: const Duration(milliseconds: 150),
                              fit: BoxFit.cover,
                              memCacheWidth: 320,
                              errorWidget: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),
                      if (watched)
                        Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      if (progress != null && progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.25,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
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
              if (!DeviceTypeService.isTv)
                DownloadButton(channel: ep.channel),
              if (!DeviceTypeService.isTv)
                IconButton(
                  tooltip: watched
                      ? 'Segna come non visto'
                      : 'Segna come visto',
                  onPressed: onToggleWatched,
                  icon: Icon(
                    watched
                        ? Icons.check_circle_rounded
                        : Icons.check_circle_outline_rounded,
                    color: watched ? AppColors.primary : AppColors.textMuted,
                    size: 26,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: card,
    );
    if (!DeviceTypeService.isTv) return tile;
    // TV: the focus ring hugs the card (no outer margin inside it, no
    // enlargement), so it never runs off the screen or over the next row.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: FocusTraversalGroup(
        child: Row(
          children: [
            Expanded(
              child: TvFocusable(
                onPressed: onTap,
                onLongPress: onToggleWatched,
                focusedScale: 1.0,
                borderRadius: BorderRadius.circular(12),
                child: card,
              ),
            ),
            const SizedBox(width: 12),
            DownloadButton(channel: episode.channel),
            TvFocusable(
              onPressed: onToggleWatched,
              focusedScale: 1.0,
              borderRadius: BorderRadius.circular(24),
              child: IconButton(
                tooltip: watched ? 'Segna come non visto' : 'Segna come visto',
                onPressed: onToggleWatched,
                icon: Icon(
                  watched ? Icons.check_circle : Icons.check_circle_outline,
                  color: watched ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surface,
    child: const Icon(
      Icons.movie_outlined,
      color: AppColors.textMuted,
      size: 28,
    ),
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
      child: Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}
