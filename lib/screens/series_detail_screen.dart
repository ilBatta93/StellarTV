import '../widgets/ui_scale.dart';

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
import '../widgets/reaction_buttons.dart';
import '../widgets/episode_card.dart';
import '../widgets/home_art.dart';
import '../widgets/trailer_button.dart';
import '../services/title_display.dart';
import '../services/series_resume_policy.dart';
import '../widgets/category_assign_button.dart';
import '../widgets/title_facets.dart';
import '../widgets/tv_wrap_navigation.dart';
import '../widgets/series_watch_sheet.dart';
import '../services/episode_metadata_service.dart';
import '../services/catalog_rating_service.dart';

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
  Future<void> _manageWatch() async {
    final details = _details;
    if (details == null) return;
    await context.read<HistoryProvider>().setSuggestionDismissed(
      widget.series.id,
      false,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SeriesWatchSheet(details: details),
    );
  }

  Widget _manageWatchButton() => TvFocusable(
    onPressed: () {
      if (_details != null) _manageWatch();
    },
    child: OutlinedButton.icon(
      onPressed: _details == null ? null : _manageWatch,
      icon: const Icon(Icons.checklist_rounded),
      label: const Text('Gestisci visione'),
    ),
  );

  Widget _watchSuggestion(HistoryProvider history) {
    final all = _details?.allEpisodes ?? const <SeriesEpisode>[];
    if (history.suggestionDismissed(widget.series.id))
      return const SizedBox.shrink();
    final started = all
        .where(
          (e) =>
              (history.entryFor(e.channel.id)?.position ?? Duration.zero) >
              const Duration(seconds: 5),
        )
        .toList();
    if (started.isEmpty) return const SizedBox.shrink();
    started.sort((a, b) => a.season.compareTo(b.season));
    final current = started.first.season;
    final previous = all
        .where((e) => e.season > 0 && e.season < current)
        .toList();
    if (previous.isEmpty ||
        previous.any(
          (e) =>
              history.isWatched(e.channel.id) ||
              (history.entryFor(e.channel.id)?.position ?? Duration.zero) >
                  Duration.zero,
        ))
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hai iniziato dalla stagione $current. Vuoi segnare viste le stagioni precedenti?',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TvFocusable(
                onPressed: () => history.setManualWatched(
                  previous.map((e) => e.channel.id),
                  true,
                  seriesId: widget.series.seriesKey ?? widget.series.id,
                ),
                child: TextButton(
                  onPressed: () => history.setManualWatched(
                    previous.map((e) => e.channel.id),
                    true,
                    seriesId: widget.series.seriesKey ?? widget.series.id,
                  ),
                  child: const Text('Segna come viste'),
                ),
              ),
              TvFocusable(
                onPressed: () =>
                    history.setSuggestionDismissed(widget.series.id, true),
                child: TextButton(
                  onPressed: () =>
                      history.setSuggestionDismissed(widget.series.id, true),
                  child: const Text('Non ora'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _item = widget.item ?? CatalogRatingService.instance.itemOf(widget.series);
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
      if (item == null || !mounted) return;
      setState(() => _item = item);
      CatalogRatingService.instance.remember(widget.series, item);
      _prepareEpisodes();
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
      _prepareEpisodes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile caricare episodi e stagioni.';
        _loading = false;
      });
    }
  }

  void _prepareEpisodes() {
    final item = _item;
    final seasons = _details?.seasons;
    if (item == null || seasons == null || _selectedSeason >= seasons.length)
      return;
    final season = seasons[_selectedSeason];
    EpisodeMetadataService.instance.prepare(item, season.number, [
      for (final e in season.episodes) e.channel,
    ]);
  }

  void _selectSeason(int i) {
    setState(() => _selectedSeason = i);
    _prepareEpisodes();
  }

  @override
  Widget build(BuildContext context) => UiScale(builder: _buildContent);

  Widget _buildContent(BuildContext context) {
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
                if (DeviceTypeService.isTv && item != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: HomeTitleArt(item: item),
                  )
                else
                  Text(
                    DeviceTypeService.isTv
                        ? displayTitle(series.displaySeriesName)
                        : series.displaySeriesName,
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
                    if (item != null && item.year.isNotEmpty)
                      _Chip(label: item.year),
                    if (item != null) ImdbRatingBadge(item),
                    _Chip(label: series.group),
                  ],
                ),
                TitleFacetsRow(item: item, channel: series),
                const SizedBox(height: 16),
                if (DeviceTypeService.isTv) ...[
                  _buildTvActions(context, isFav),
                  const SizedBox(height: 16),
                ] else ...[
                  _buildPlaybackButton(context),
                  _manageWatchButton(),
                  const SizedBox(height: 16),
                ],
                if (!DeviceTypeService.isTv && item != null)
                  TrailerButton(item: item),
                if (!DeviceTypeService.isTv)
                  CategoryAssignButton(item: widget.series),
                if (_item case final reactionItem?)
                  ReactionButtons(item: reactionItem),
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _watchSuggestion(context.watch<HistoryProvider>()),
          ),
        ),
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
              message: 'Questa serie TV non ha episodi disponibili.',
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
                    onPressed: () => _selectSeason(i),
                    child: ChoiceChip(
                      label: Text(seasons[i].name),
                      selected: selected,
                      onSelected: (_) => _selectSeason(i),
                      labelStyle: TextStyle(
                        fontFamily: DeviceTypeService.isTv ? 'Manrope' : null,
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
          SliverToBoxAdapter(
            child: HorizontalRow(
              key: ValueKey(currentSeason.number),
              horizontalFocusFilter: (node) => node is EpisodePlaybackFocusNode,
              height: 390,
              itemCount: currentSeason.episodes.length,
              itemBuilder: (context, i) {
                final ep = currentSeason.episodes[i];
                final history = context.watch<HistoryProvider>();
                final entry = history.entryFor(ep.channel.id);
                return EpisodeCard(
                  episode: ep,
                  seriesTmdbId: _item?.id,
                  seriesImage: _item?.posterUrl ?? widget.series.logo,
                  progress: entry?.isWatched == true ? null : entry?.progress,
                  watched: history.isWatched(ep.channel.id),
                  onToggleWatched: () {
                    final h = context.read<HistoryProvider>();
                    if (h.isWatched(ep.channel.id)) {
                      h.setManualWatched(
                        [ep.channel.id],
                        false,
                        seriesId: widget.series.seriesKey ?? widget.series.id,
                      );
                    } else {
                      h.setManualWatched(
                        [ep.channel.id],
                        true,
                        seriesId: widget.series.seriesKey ?? widget.series.id,
                      );
                    }
                  },
                  onPlay: () => playChannel(
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
    final replay = latestSeriesReplay(all, history.entries);
    if (replay != null) return replay;
    final hasManual = all.any(
      (e) => history.manualWatched(e.channel.id) != null,
    );
    var lastWatched = -1;
    for (final (i, e) in all.indexed) {
      if (history.isWatched(e.channel.id)) {
        lastWatched = i;
        continue;
      }
      final entry = history.entryFor(e.channel.id);
      if (entry == null) continue;
      if ((entry.resumePosition ?? Duration.zero) > Duration.zero) {
        return e;
      }
    }
    if (hasManual)
      return all.where((e) => !history.isWatched(e.channel.id)).firstOrNull ??
          all.first;
    return lastWatched + 1 < all.length ? all[lastWatched + 1] : all.first;
  }

  /// Countdown and playback always refer to the same selected episode.
  Widget _buildPlaybackButton(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    final episode = _resumeEpisode(history);
    final entry = episode == null ? null : history.entryFor(episode.channel.id);
    final started = entry != null;
    final remaining = entry?.startedRemainingMinutes;
    final baseLabel = episode == null
        ? (_loading ? 'Caricamento episodi...' : 'Guarda ora')
        : '${started ? 'Riprendi' : 'Guarda'} ${episode.code}';
    final label = remaining == null
        ? baseLabel
        : '$baseLabel · $remaining min rim.';
    void play() {
      if (episode == null) return;
      playChannel(
        context,
        episode.channel,
        queue: [for (final e in _details?.allEpisodes ?? const []) e.channel],
        startAt: history.entryFor(episode.channel.id)?.resumePosition,
      );
    }

    return TvFocusable(
      autofocus: DeviceTypeService.isTv,
      onPressed: play,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(label, textAlign: TextAlign.center),
        onPressed: episode == null ? null : play,
      ),
    );
  }

  /// TV only: focusable buttons at the top of the page (first focus).
  Widget _buildTvActions(BuildContext context, bool isFav) {
    final app = context.read<AppProvider>();
    return TvWrapNavigation(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildPlaybackButton(context),
          _manageWatchButton(),
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
          if (_item case final item?) TrailerButton(item: item),
          CategoryAssignButton(item: widget.series),
        ],
      ),
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
          subtitle: 'Disponibili sul dispositivo',
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
