import '../providers/ui_settings.dart';
import '../models/home_layout_preferences.dart';
import '../widgets/home_presentation.dart';
import '../widgets/home_art.dart';
import '../widgets/tv_home_layout.dart';
import '../services/history_episode_label.dart';
import '../widgets/tv_home_rows.dart';
import '../services/title_display.dart';
import '../services/series_resume_policy.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/image_warmup_service.dart';
import '../services/tv_render_policy.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../widgets/expiry_banner.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../models/series_details.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/reactions_provider.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import '../widgets/tv_focusable.dart';

/// A watch-history entry paired with the channel it belongs to.
typedef ResumeItem = (HistoryEntry, Channel);

ResumeItem? latestHistoryResume(List<HistoryEntry> entries, AppProvider app) {
  final ordered = entries.where((e) => !e.isLive).toList()
    ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
  for (final e in ordered) {
    final channel =
        app.channelById(e.contentId) ??
        Channel(
          id: e.contentId,
          name: e.title,
          url: e.url,
          logo: e.posterUrl,
          group: e.group,
          type: e.type,
          seriesKey: e.seriesKey.isEmpty ? null : e.seriesKey,
          seriesName: e.seriesName.isEmpty ? null : e.seriesName,
        );
    if (channel.url.isEmpty && !channel.isSeriesFolder) continue;
    if (!app.kidsMode || app.isKidsContent(channel)) return (e, channel);
  }
  return null;
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  /// Finished series episodes already checked for a following sequential
  /// episode (contentId -> has next). Checked one at a time, only for
  /// entries whose latest episode is complete, so the catalog is never
  /// rescanned on every frame.
  final Map<SeriesReplayKey, bool> _hasNext = {};
  final List<(HistoryEntry, Channel, SeriesReplayKey)> _pendingNext = [];
  bool _checkingNext = false;
  AppProvider? _nextApp;
  int _nextGeneration = 0;
  Set<SeriesReplayKey> _activeReplayKeys = {};

  void _catalogChanged() {
    _nextGeneration++;
    _hasNext.clear();
    _pendingNext.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppProvider>();
    if (identical(app, _nextApp)) return;
    _nextApp?.removeListener(_catalogChanged);
    _nextApp = app;
    app.addListener(_catalogChanged);
    _catalogChanged();
  }

  @override
  void dispose() {
    _nextApp?.removeListener(_catalogChanged);
    _nextGeneration++;
    _pendingNext.clear();
    super.dispose();
  }

  void _queueNextCheck(HistoryEntry e, Channel folder) {
    final key = seriesReplayKey(context.read<HistoryProvider>().profileId, e);
    if (!_activeReplayKeys.contains(key)) return;
    if (_hasNext.containsKey(key) || _pendingNext.any((p) => p.$3 == key)) {
      return;
    }
    _pendingNext.add((e, folder, key));
    if (!_checkingNext) _drainNextChecks();
  }

  Future<void> _drainNextChecks() async {
    _checkingNext = true;
    while (_pendingNext.isNotEmpty && mounted) {
      final (entry, folder, key) = _pendingNext.removeAt(0);
      final generation = _nextGeneration;
      try {
        final next = await _findNextEpisode(context, entry, folder);
        if (!mounted) break;
        if (generation != _nextGeneration || !_activeReplayKeys.contains(key))
          continue;
        _hasNext[key] = next != null;
        if (next == null) setState(() {});
      } catch (_) {
        if (!mounted) break;
        if (generation != _nextGeneration || !_activeReplayKeys.contains(key))
          continue;
        // Unknown: keep the series visible.
        _hasNext[key] = true;
      }
    }
    _checkingNext = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final discover = context.read<DiscoverProvider>();
      if (!discover.hasData) discover.load();
    });
  }

  @override
  Widget build(BuildContext context) =>
      HomePresentation(child: Builder(builder: _buildHome));

  Widget _buildHome(BuildContext context) {
    final ui = context.watch<UiSettings>();
    final app = context.watch<AppProvider>();
    final discover = context.watch<DiscoverProvider>();
    final history = context.watch<HistoryProvider>();
    final reactions = context.watch<ReactionsProvider>();
    _activeReplayKeys = {
      for (final entry in history.continueWatching)
        seriesReplayKey(history.profileId, entry),
    };
    _hasNext.removeWhere((key, _) => !_activeReplayKeys.contains(key));
    // Episodes may not be indexed after a restart: rebuild them from the
    // history entry so watched series still feed "Serie consigliate".
    final entries = history.entries;
    final watched = entries
        .map(
          (e) =>
              app.channelById(e.contentId) ??
              (e.type == ContentType.series || e.type == ContentType.anime
                  ? Channel(
                      id: e.contentId,
                      name: e.title,
                      url: e.url,
                      logo: e.posterUrl,
                      group: e.group,
                      type: e.type,
                      seriesKey: e.seriesKey.isEmpty ? null : e.seriesKey,
                      seriesName: e.seriesName.isEmpty ? null : e.seriesName,
                    )
                  : null),
        )
        .whereType<Channel>()
        .where((c) => !app.kidsMode || app.isKidsContent(c))
        .toList();
    // Resolve each started item to its playlist channel; when the channel is
    // not indexed (e.g. series episodes after a restart) rebuild it from the
    // history entry itself, which stores url, title and poster.
    final started = <ResumeItem>[
      for (final e in history.continueWatching)
        if (app.channelById(e.contentId) ??
                // Cloud-restored episodes carry no stream address: fall back
                // to their series folder so "Serie in corso" stays visible.
                ((e.type == ContentType.series ||
                            e.type == ContentType.anime) &&
                        e.seriesKey.isNotEmpty
                    ? app.seriesFolderFor(e.seriesKey, wait: false)
                    : null) ??
                (e.url.isEmpty
                    ? null
                    : Channel(
                        id: e.contentId,
                        name: e.title,
                        url: e.url,
                        logo: e.posterUrl,
                        group: e.group,
                        type: e.type,
                        seriesKey: e.seriesKey.isEmpty ? null : e.seriesKey,
                        seriesName: e.seriesName.isEmpty ? null : e.seriesName,
                      ))
            case final c?)
          if ((!app.kidsMode || app.isKidsContent(c)) &&
              // Partial replays stay visible; only the actual final episode ends the sequence.
              (!replayEpisodeComplete(e) ||
                  _hasNext[seriesReplayKey(history.profileId, e)] != false))
            (e, c),
    ];
    for (final (e, c) in started) {
      final isEp = e.type == ContentType.series || e.type == ContentType.anime;
      if (!isEp ||
          !replayEpisodeComplete(e) ||
          _hasNext.containsKey(seriesReplayKey(history.profileId, e)))
        continue;
      final folder = e.seriesKey.isNotEmpty
          ? app.seriesFolderFor(e.seriesKey, wait: false)
          : (c.isSeriesFolder ? c : null);
      if (folder != null) {
        final generation = _nextGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _nextGeneration)
            _queueNextCheck(e, folder);
        });
      }
    }
    // "Continua a guardare" rows show at most 50 titles each.
    final startedMovies = <ResumeItem>[
      for (final it in started)
        if (it.$1.type == ContentType.movie) it,
    ].take(ui.homeRecentLimit).toList();
    final startedSeries = <ResumeItem>[
      for (final it in started)
        if (it.$1.type == ContentType.series || it.$1.type == ContentType.anime)
          it,
    ].take(ui.homeRecentLimit).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        context.read<DiscoverProvider>().loadForYou(
          watched,
          liked: reactions.liked
              .where(
                (i) =>
                    !app.kidsMode ||
                    (app.isAvailable(i) && app.isTmdbAllowed(i)),
              )
              .toList(),
          disliked: reactions.disliked,
          reactionSignature: reactions.signature,
        );
    });

    if (discover.error != null && !discover.hasData) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Catalogo non disponibile',
        message: discover.error!,
        action: ElevatedButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Riprova'),
          onPressed: () => discover.load(force: true),
        ),
      );
    }

    if (!discover.hasData) return const _DiscoverSkeleton();

    // Only titles that can actually be watched with the playlist.
    List<TmdbItem> available(List<TmdbItem> items) => items
        .where(
          (item) =>
              app.isAvailable(item) &&
              app.isTmdbAllowed(item) &&
              !reactions.disliked.contains(item.key),
        )
        .take(10)
        .toList();
    final topMovies = available(discover.topMovies);
    final topSeries = available(discover.topSeries);
    final banner = [...topMovies.take(6), ...topSeries.take(4)];

    if (DeviceTypeService.isTv) {
      // Same sections as the phone Home (Top 10 with Film / Serie TV switch,
      // per-platform Top 10, recommendations), laid out for the remote.
      return _TvDiscover(
        profileId: context.watch<ProfileProvider>().selected?.id,
        banner: banner,
        initialHistory: latestHistoryResume(entries, app),
        startedMovies: startedMovies,
        startedSeries: startedSeries,
        forYou: discover.forYou
            .where(
              (item) =>
                  app.isAvailable(item) &&
                  app.isTmdbAllowed(item) &&
                  !reactions.disliked.contains(item.key),
            )
            .toList(),
        forYouSource: discover.forYouSource,
        forYouSeries: discover.forYouSeries
            .where(
              (item) =>
                  app.isAvailable(item) &&
                  app.isTmdbAllowed(item) &&
                  !reactions.disliked.contains(item.key),
            )
            .toList(),
        forYouSeriesSource: discover.forYouSeriesSource,
        tops: [
          (
            'Top 10 della settimana',
            'In tendenza e disponibili sul dispositivo',
            AppColors.primary,
            topMovies,
            topSeries,
          ),
          for (final p in StreamingPlatform.all)
            (
              'Top 10 su ${p.name}',
              null,
              p.color,
              available(discover.platformTop(p).movies),
              available(discover.platformTop(p).series),
            ),
        ],
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => discover.load(force: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const ExpiryBanner(),
          if (banner.isNotEmpty) _Top10Banner(items: banner),
          if (startedMovies.isNotEmpty) ...[
            SectionHeader(
              title: 'Film che stai guardando',
              leading: Icon(
                Icons.movie_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            _HistoryRow(items: startedMovies),
          ],
          if (startedSeries.isNotEmpty) ...[
            const SectionHeader(
              title: 'Serie TV che stai guardando',
              leading: Icon(
                Icons.video_library_outlined,
                color: AppColors.secondary,
                size: 20,
              ),
            ),
            _HistoryRow(items: startedSeries),
          ],
          if (discover.forYou
              .where(
                (item) =>
                    app.isAvailable(item) &&
                    app.isTmdbAllowed(item) &&
                    !reactions.disliked.contains(item.key),
              )
              .isNotEmpty) ...[
            SectionHeader(
              title: 'Film consigliati per te',
              subtitle: 'Perché hai guardato ${discover.forYouSource}',
              leading: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.secondary,
                size: 20,
              ),
            ),
            _PosterRow(
              items: discover.forYou
                  .where(
                    (item) =>
                        app.isAvailable(item) &&
                        app.isTmdbAllowed(item) &&
                        !reactions.disliked.contains(item.key),
                  )
                  .toList(),
            ),
          ],
          if (discover.forYouSeries
              .where(
                (item) =>
                    app.isAvailable(item) &&
                    app.isTmdbAllowed(item) &&
                    !reactions.disliked.contains(item.key),
              )
              .isNotEmpty) ...[
            SectionHeader(
              title: 'Serie consigliate per te',
              subtitle: 'Perché hai guardato ${discover.forYouSeriesSource}',
              leading: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.secondary,
                size: 20,
              ),
            ),
            _PosterRow(
              items: discover.forYouSeries
                  .where(
                    (item) =>
                        app.isAvailable(item) &&
                        app.isTmdbAllowed(item) &&
                        !reactions.disliked.contains(item.key),
                  )
                  .toList(),
            ),
          ],
          _TopSection(
            title: 'Top 10 della settimana',
            subtitle: 'In tendenza e disponibili sul dispositivo',
            color: AppColors.primary,
            movies: topMovies,
            series: topSeries,
          ),
          for (final p in StreamingPlatform.all)
            _TopSection(
              title: 'Top 10 su ${p.name}',
              color: p.color,
              movies: available(discover.platformTop(p).movies),
              series: available(discover.platformTop(p).series),
            ),
          if (discover.isLoading)
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A Top 10 block with a Film / Serie TV switch. Hidden when none of its
/// titles is in the playlist; the switch only shows the kinds available.
class _TopSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Color color;
  final List<TmdbItem> movies;
  final List<TmdbItem> series;

  const _TopSection({
    required this.title,
    this.subtitle,
    required this.color,
    required this.movies,
    required this.series,
  });

  @override
  State<_TopSection> createState() => _TopSectionState();
}

class _TopSectionState extends State<_TopSection> {
  bool _showSeries = false;

  @override
  Widget build(BuildContext context) {
    final hasMovies = widget.movies.isNotEmpty;
    final hasSeries = widget.series.isNotEmpty;
    if (!hasMovies && !hasSeries) return const SizedBox.shrink();
    final showSeries = hasSeries && (_showSeries || !hasMovies);
    final items = showSeries ? widget.series : widget.movies;

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (hasMovies && hasSeries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _segment(
                      'Film',
                      !showSeries,
                      () => setState(() => _showSeries = false),
                    ),
                    _segment(
                      'Serie TV',
                      showSeries,
                      () => setState(() => _showSeries = true),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _RankedRow(
              key: ValueKey('${widget.title}_$showSeries'),
              items: items,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? widget.color : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? (widget.color.computeLuminance() > 0.6
                      ? Colors.black
                      : Colors.white)
                : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Top10Banner extends StatefulWidget {
  final List<TmdbItem> items;

  const _Top10Banner({required this.items});

  @override
  State<_Top10Banner> createState() => _Top10BannerState();
}

class _Top10BannerState extends State<_Top10Banner> {
  late final PageController _controller;
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_controller.hasClients || widget.items.isEmpty) return;
      final next = (_page + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio:
              4 /
              (3.4 *
                  context.watch<UiSettings>().homeBannerSize.fraction /
                  0.43),
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) =>
                _BannerSlide(item: widget.items[i], rank: i + 1),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page
                      ? AppColors.primary
                      : AppColors.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BannerSlide extends StatelessWidget {
  final TmdbItem item;
  final int rank;

  const _BannerSlide({required this.item, required this.rank});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final match = app.findChannelFor(item);
    return Pressable(
      onTap: () => openTmdbItem(context, item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PosterImage(url: item.backdropUrl),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0xCC09090D),
                  AppColors.background,
                ],
                stops: [0.35, 0.75, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.isMovie ? 'FILM IN TENDENZA' : 'SERIE IN TENDENZA',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                HomeTitleArt(item: item),
                const SizedBox(height: 8),
                if (context.watch<UiSettings>().homeOverview)
                  Text(
                    item.overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (match != null) ...[
                      ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Guarda'),
                        onPressed: () => match.isSeriesFolder
                            ? openSeries(context, match, item: item)
                            : playChannel(context, match),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton.icon(
                      icon: const Icon(Icons.info_outline_rounded),
                      label: const Text('Dettagli'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => openTmdbItem(context, item),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final List<ResumeItem> items;
  final ValueChanged<ResumeItem>? onFocus;

  const _HistoryRow({required this.items, this.onFocus});

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    return HorizontalRow(
      height: tv
          ? TvHomeLayout.maybeOf(context)?.carouselHeight ??
                homeRowHeight(context)
          : homeRowHeight(context),
      spacing: tv ? 20 : 12,
      itemCount: items.length,
      itemBuilder: (context, i) => _HistoryCard(
        item: items[i],
        onFocus: onFocus == null ? null : () => onFocus?.call(items[i]),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ResumeItem item;
  final VoidCallback? onFocus;

  const _HistoryCard({required this.item, this.onFocus});

  @override
  Widget build(BuildContext context) {
    final (entry, channel) = item;
    final progress = entry.progress ?? 0.0;
    final isEpisode = entry.type != ContentType.movie;
    final app = context.read<AppProvider>();
    final seriesKey =
        channel.seriesKey ?? (entry.seriesKey.isEmpty ? null : entry.seriesKey);
    final folder = isEpisode && seriesKey != null
        ? app.seriesFolderFor(seriesKey, wait: false)
        : null;
    // Series show the standard series poster, not the episode still.
    final poster = [
      if (isEpisode) folder?.logo ?? '',
      if (isEpisode) entry.seriesPoster,
      channel.logo,
      entry.posterUrl,
    ].firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final seriesName =
        folder?.displaySeriesName ??
        (entry.seriesName.isNotEmpty ? entry.seriesName : null);
    final code = historyEpisodeLabel(
      type: entry.type,
      season: channel.season,
      episode: channel.episode,
      historyTitle: entry.title,
      channelTitle: channel.name,
    );
    final minutesLeft = entry.remainingMovieMinutes;
    final finished = isEpisode && replayEpisodeComplete(entry);
    final trailing = finished
        ? 'Prossimo'
        : isEpisode
        ? code
        : minutesLeft == null
        ? null
        : '$minutesLeft min rim.';
    // Clean name only: season/episode move to the badge on the right.
    final title = isEpisode && seriesName != null
        ? displayTitle(seriesName)
        : displayTitle(channel.name);
    final playable = seriesKey != null && channel.seriesKey == null
        ? channel.copyWith(seriesKey: seriesKey)
        : channel;
    // Resume the exact movie/episode from where it was left.
    return HomeHistoryArtwork(
      title: seriesName ?? channel.name,
      isMovie: !isEpisode,
      fallback: poster,
      builder: (image) => HomeLandscapeCard(
        title: title,
        image: image,
        progress: finished ? 0.0 : progress,
        trailing: trailing,
        onFocus: onFocus,
        onTap: () => finished
            ? _playNextEpisode(context, entry, channel, folder)
            : playChannel(
                context,
                playable,
                startAt: entry.resumePosition ?? entry.position,
              ),
      ),
    );
  }
}

/// Immediate next episode, including previously watched ones; null only at the end.
Future<SeriesEpisode?> _findNextEpisode(
  BuildContext context,
  HistoryEntry entry,
  Channel folder,
) async {
  final app = context.read<AppProvider>();
  final details = await app.loadSeriesDetails(folder);
  final all = details.allEpisodes;
  final ch = app.channelById(entry.contentId);
  return nextEpisodeInSequence(
    all,
    entry.contentId,
    season: ch?.season,
    number: ch?.episode,
  );
}

/// Plays the episode after a finished one; opens the series page when the
/// next episode cannot be resolved (end of series or details unavailable).
Future<void> _playNextEpisode(
  BuildContext context,
  HistoryEntry entry,
  Channel channel,
  Channel? folder,
) async {
  if (folder == null) {
    openChannel(context, channel);
    return;
  }
  final history = context.read<HistoryProvider>();
  try {
    final next = await _findNextEpisode(context, entry, folder);
    if (!context.mounted) return;
    if (next == null) {
      openChannel(context, folder);
      return;
    }
    final ch = next.channel;
    playChannel(
      context,
      ch.seriesKey == null
          ? ch.copyWith(seriesKey: folder.seriesKey ?? folder.id)
          : ch,
      startAt: history.entryFor(ch.id)?.resumePosition,
    );
  } catch (_) {
    if (context.mounted) openChannel(context, folder);
  }
}

class _PosterRow extends StatelessWidget {
  final List<TmdbItem> items;

  const _PosterRow({required this.items});

  @override
  Widget build(BuildContext context) {
    PosterMemoryWarmup.warm(
      context,
      items.take(8).map((i) => homePosterUrl(context, i)),
    );
    return HorizontalRow(
      height: tmdbPosterRowHeight(context),
      itemCount: items
          .take(context.watch<UiSettings>().homeRecommendationLimit)
          .length,
      itemBuilder: (context, i) => TmdbPosterCard(
        item: items[i],
        onTap: () => openTmdbItem(context, items[i]),
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final List<TmdbItem> items;

  const _RankedRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return HorizontalRow(
      height: TvHomeLayout.maybeOf(context)?.rankedHeight ?? 196,
      spacing: 4,
      itemCount: items.length,
      itemBuilder: (context, i) => RankedPosterCard(
        item: items[i],
        rank: i + 1,
        onTap: () => openTmdbItem(context, items[i]),
      ),
    );
  }
}

class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        block(double.infinity, 260),
        for (var r = 0; r < 2; r++) ...[
          const SizedBox(height: 24),
          block(140, 16),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(child: block(double.infinity, 170)),
                if (i < 2) const SizedBox(width: 12),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TV-only Home: large hero driven by the focused title, rows below.
// ---------------------------------------------------------------------------

void _revealTvHeading(BuildContext context) {
  final scroll = Scrollable.maybeOf(context);
  final target = context.findRenderObject();
  if (scroll == null || target == null) return;
  final viewport = RenderAbstractViewport.maybeOf(target);
  if (viewport == null) return;
  final position = scroll.position;
  final headingOffset = viewport.getOffsetToReveal(target, 0).offset;
  // Snap to the enclosing full-height section, not the heading’s inner padding.
  final extent = position.viewportDimension;
  final offset = extent > 0
      ? (headingOffset / extent).floor() * extent
      : headingOffset;
  position.jumpTo(
    offset.clamp(position.minScrollExtent, position.maxScrollExtent),
  );
}

typedef TvTopSpec = (
  String title,
  String? subtitle,
  Color color,
  List<TmdbItem> movies,
  List<TmdbItem> series,
);

class _TvDiscover extends StatefulWidget {
  final String? profileId;
  final List<TmdbItem> banner;
  final ResumeItem? initialHistory;
  final List<ResumeItem> startedMovies;
  final List<ResumeItem> startedSeries;
  final List<TmdbItem> forYou;
  final String? forYouSource;
  final List<TmdbItem> forYouSeries;
  final String? forYouSeriesSource;
  final List<TvTopSpec> tops;

  const _TvDiscover({
    required this.profileId,
    required this.banner,
    required this.initialHistory,
    required this.startedMovies,
    required this.startedSeries,
    required this.forYou,
    required this.forYouSource,
    required this.forYouSeries,
    required this.forYouSeriesSource,
    required this.tops,
  });

  @override
  State<_TvDiscover> createState() => _TvDiscoverState();
}

class _TvDiscoverState extends State<_TvDiscover> {
  late final ValueNotifier<TmdbItem?> _hero;
  final ValueNotifier<String?> _heroNote = ValueNotifier(null);
  Timer? _debounce;
  int _heroRequest = 0;
  bool _userFocused = false;
  String? _seededHistory;
  final Map<String, TmdbItem?> _historyInfo = {};

  @override
  void initState() {
    super.initState();
    _hero = ValueNotifier(_firstHero());
    _seedInitialHistory();
  }

  TmdbItem? _firstHero() {
    TmdbItem? first;
    if (widget.banner.isNotEmpty) {
      first = widget.banner.first;
    } else if (widget.forYou.isNotEmpty) {
      first = widget.forYou.first;
    } else if (widget.forYouSeries.isNotEmpty) {
      first = widget.forYouSeries.first;
    } else {
      for (final t in widget.tops) {
        final items = t.$4.isNotEmpty ? t.$4 : t.$5;
        if (items.isNotEmpty) {
          first = items.first;
          break;
        }
      }
    }
    return first;
  }

  @override
  void didUpdateWidget(covariant _TvDiscover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _heroRequest++;
      _debounce?.cancel();
      _historyInfo.clear();
      _userFocused = false;
      _seededHistory = null;
      _hero.value = _firstHero();
    }
    _seedInitialHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hero.dispose();
    _heroNote.dispose();
    super.dispose();
  }

  // Debounced so scrolling quickly with the remote does not load every
  // backdrop on the way.
  void _focus(TmdbItem item) {
    _userFocused = true;
    _heroRequest++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        _heroNote.value = null;
        if (_hero.value?.key != item.key) _hero.value = item;
      }
    });
  }

  void _seedInitialHistory() {
    final resume = widget.initialHistory;
    if (_userFocused || resume == null || _seededHistory == resume.$1.contentId)
      return;
    _seededHistory = resume.$1.contentId;
    _focusHistory(resume, initial: true);
  }

  void _focusHistory(ResumeItem resume, {bool initial = false}) {
    if (!initial) _userFocused = true;
    final (entry, channel) = resume;
    final movie = entry.type == ContentType.movie;
    final title = movie
        ? channel.name
        : (entry.seriesName.isNotEmpty
              ? entry.seriesName
              : channel.displaySeriesName);
    final key = '${movie ? 'movie' : 'tv'}_$title';
    final request = ++_heroRequest;
    final tmdb = context.read<DiscoverProvider>().tmdb;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final item = _historyInfo.containsKey(key)
          ? _historyInfo[key]
          : await tmdb
                .findByTitle(title, isMovie: movie)
                .catchError((_) => null);
      if (!mounted || request != _heroRequest) return;
      _historyInfo[key] = item;
      _heroNote.value = _historyNote(resume);
      _hero.value =
          item ??
          TmdbItem(
            id: -channel.id.hashCode.abs(),
            mediaType: movie ? 'movie' : 'tv',
            title: title,
            overview: channel.group,
            posterPath: null,
            backdropPath: null,
            voteAverage: 0,
            popularity: 0,
            releaseDate: '',
          );
    });
  }

  /// Episode coordinates or minutes left, plus progress, for the hero banner.
  static String? _historyNote(ResumeItem resume) {
    final (entry, channel) = resume;
    final parts = <String>[];
    if (entry.type == ContentType.movie) {
      final left = entry.remainingMovieMinutes;
      if (left != null) parts.add('$left min rimanenti');
    } else {
      final code = historyEpisodeLabel(
        type: entry.type,
        season: channel.season,
        episode: channel.episode,
        historyTitle: entry.title,
        channelTitle: channel.name,
      );
      if (code != null && code.isNotEmpty) parts.add(code);
    }
    final p = entry.progress;
    if (p != null && p > 0)
      parts.add('${(p.clamp(0.0, 1.0) * 100).round()}% visto');
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  void _revealHeading(BuildContext rowContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !rowContext.mounted) return;
      _revealTvHeading(rowContext);
    });
  }

  Widget _historySection(String title, List<ResumeItem> items) => Builder(
    key: ValueKey(title),
    builder: (rowContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TvRowTitle(title),
        _HistoryRow(
          items: items,
          onFocus: (resume) {
            _focusHistory(resume);
            _revealHeading(rowContext);
          },
        ),
      ],
    ),
  );

  Widget _row(String title, List<TmdbItem> items, {String? subtitle}) {
    return Builder(
      key: ValueKey(title),
      builder: (rowContext) =>
          _posterRow(title, items, rowContext, subtitle: subtitle),
    );
  }

  Widget _posterRow(
    String title,
    List<TmdbItem> items,
    BuildContext rowContext, {
    String? subtitle,
  }) {
    PosterMemoryWarmup.warm(
      rowContext,
      items.take(8).map((i) => homePosterUrl(rowContext, i)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TvRowTitle(title, subtitle: subtitle),
        HorizontalRow(
          // Poster + two full title lines + focus frame, never clipped.
          height: tmdbPosterRowHeight(rowContext, mobile: 212),
          spacing: 20,
          itemCount: items
              .take(context.watch<UiSettings>().homeRecommendationLimit)
              .length,
          itemBuilder: (context, i) => TmdbPosterCard(
            item: items[i],
            onTap: () => openTmdbItem(context, items[i]),
            onFocus: () {
              _focus(items[i]);
              // Only the settled banner loads its logo; no adjacent predecode.
              _revealHeading(rowContext);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Reserve the synopsis first, then size every carousel to the actual
        // remaining height. Fixed catalog sizes must not squeeze out the plot.
        final heroHeight =
            c.maxHeight * context.watch<UiSettings>().homeBannerSize.fraction;
        return TvHomeLayout(
          rowHeight: c.maxHeight - heroHeight,
          captionHeight: MediaQuery.textScalerOf(context).scale(14) * 1.2 * 3,
          showTitles: context.watch<UiSettings>().homeTitles,
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<TmdbItem?>(
                  valueListenable: _hero,
                  builder: (_, item, _) => ValueListenableBuilder<bool>(
                    valueListenable: TvImageMemoryGuard.reducedRendering,
                    builder: (_, pressure, _) =>
                        TvRenderPolicy.backdropAllowed(
                          isTv: true,
                          memoryPressure: pressure,
                        )
                        ? _TvHeroBackdrop(item: item)
                        : const ColoredBox(color: AppColors.background),
                  ),
                ),
              ),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: heroHeight,
                    child: Column(
                      children: [
                        const ExpiryBanner(),
                        Expanded(
                          child: ValueListenableBuilder<TmdbItem?>(
                            valueListenable: _hero,
                            builder: (_, item, _) =>
                                ValueListenableBuilder<String?>(
                                  valueListenable: _heroNote,
                                  builder: (_, note, _) =>
                                      _TvHeroInfo(item: item, note: note),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TvHomeRows(
                      sections: [
                        if (widget.startedSeries.isNotEmpty)
                          _historySection(
                            'Serie viste di recente',
                            widget.startedSeries,
                          ),
                        if (widget.startedMovies.isNotEmpty)
                          _historySection(
                            'Film visti di recente',
                            widget.startedMovies,
                          ),
                        if (widget.forYou.isNotEmpty)
                          _row(
                            'Film consigliati per te',
                            widget.forYou,
                            subtitle: widget.forYouSource == null
                                ? null
                                : 'Perché hai guardato '
                                      '${displayTitle(widget.forYouSource ?? "")}',
                          ),
                        if (widget.forYouSeries.isNotEmpty)
                          _row(
                            'Serie consigliate per te',
                            widget.forYouSeries,
                            subtitle: widget.forYouSeriesSource == null
                                ? null
                                : 'Perché hai guardato '
                                      '${displayTitle(widget.forYouSeriesSource ?? "")}',
                          ),
                        for (final t in widget.tops)
                          _TvTopRow(
                            key: ValueKey(t.$1),
                            spec: t,
                            onFocusItem: _focus,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// TV version of the phone "Top 10" block: title, a Film / Serie TV switch
/// reachable with the remote (Up from the posters, Left/Right to switch) and
/// the ranked posters.
class _TvTopRow extends StatefulWidget {
  final TvTopSpec spec;
  final ValueChanged<TmdbItem> onFocusItem;

  const _TvTopRow({super.key, required this.spec, required this.onFocusItem});

  @override
  State<_TvTopRow> createState() => _TvTopRowState();
}

class _TvTopRowState extends State<_TvTopRow> {
  bool _showSeries = false;
  final _headingKey = GlobalKey();
  final _movieFocus = TvHomeSelectorNode('top movies');
  final _seriesFocus = TvHomeSelectorNode('top series');
  final _postersKey = GlobalKey();
  @override
  void dispose() {
    _movieFocus.dispose();
    _seriesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, color, movies, series) = widget.spec;
    final hasMovies = movies.isNotEmpty;
    final hasSeries = series.isNotEmpty;
    if (!hasMovies && !hasSeries) return const SizedBox.shrink();
    final showSeries = hasSeries && (_showSeries || !hasMovies);
    final items = showSeries ? series : movies;
    _movieFocus.selected = !showSeries;
    _seriesFocus.selected = showSeries;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent)
          return KeyEventResult.ignored;
        final focus = FocusManager.instance.primaryFocus;
        if (focus != _movieFocus && focus != _seriesFocus)
          return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          final toSeries = key == LogicalKeyboardKey.arrowRight;
          if (hasMovies && hasSeries) {
            setState(() => _showSeries = toSeries);
            (toSeries ? _seriesFocus : _movieFocus).requestFocus();
            widget.onFocusItem((toSeries ? series : movies).first);
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          final posterContext = _postersKey.currentContext;
          if (posterContext != null) {
            final row = Focus.of(posterContext);
            row.traversalDescendants
                .where((n) => n.canRequestFocus)
                .firstOrNull
                ?.requestFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            key: _headingKey,
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasMovies || hasSeries) ...[
                  const SizedBox(width: 24),
                  if (hasMovies)
                    _chip('Film', _movieFocus, !showSeries, () {
                      setState(() => _showSeries = false);
                    }),
                  const SizedBox(width: 12),
                  if (hasSeries)
                    _chip('Serie TV', _seriesFocus, showSeries, () {
                      setState(() => _showSeries = true);
                    }),
                ],
              ],
            ),
          ),
          Focus(
            key: ValueKey('${title}_$showSeries'),
            canRequestFocus: false,
            skipTraversal: true,
            child: Builder(
              builder: (_) => HorizontalRow(
                key: _postersKey,
                height: TvHomeLayout.maybeOf(context)?.rankedHeight ?? 204,
                spacing: 16,
                itemCount: items.length,
                itemBuilder: (context, i) => Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    if ((hasMovies || hasSeries) &&
                        event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      if (event is KeyDownEvent || event is KeyRepeatEvent)
                        (showSeries ? _seriesFocus : _movieFocus)
                            .requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: RankedPosterCard(
                    item: items[i],
                    rank: i + 1,
                    onTap: () => openTmdbItem(context, items[i]),
                    onFocus: () {
                      widget.onFocusItem(items[i]);
                      // Only the settled banner loads its logo; no adjacent predecode.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final heading = _headingKey.currentContext;
                        if (mounted && heading != null)
                          _revealTvHeading(heading);
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    FocusNode focus,
    bool selected,
    VoidCallback onTap,
  ) {
    return TvFocusable(
      focusNode: focus,
      revealOnFocus: false,
      onFocusChange: (focused) {
        if (!focused) return;
        final choices = focus == _seriesFocus ? widget.spec.$5 : widget.spec.$4;
        if (choices.isNotEmpty) widget.onFocusItem(choices.first);
      },
      onPressed: () {
        onTap();
        final choices = focus == _seriesFocus ? widget.spec.$5 : widget.spec.$4;
        if (choices.isNotEmpty) widget.onFocusItem(choices.first);
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TvRowTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _TvRowTitle(this.title, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Sora',
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Sora',
                  color: AppColors.textSecondary.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TvHeroBackdrop extends StatelessWidget {
  final TmdbItem? item;

  const _TvHeroBackdrop({required this.item});

  @override
  Widget build(BuildContext context) {
    // Full-screen artwork; scrims keep the menu, the text and the rows
    // readable without cropping the image into a corner.
    return RepaintBoundary(
      child: item == null
          ? const SizedBox.expand()
          : Stack(
              key: ValueKey(item!.key),
              fit: StackFit.expand,
              children: [
                PosterImage(url: item!.backdropUrl),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.background,
                        AppColors.background.withValues(alpha: 0.82),
                        AppColors.background.withValues(alpha: 0.55),
                        AppColors.background,
                      ],
                      stops: const [0, 0.3, 0.6, 1],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _TvHeroInfo extends StatelessWidget {
  final TmdbItem? item;
  final String? note;

  const _TvHeroInfo({required this.item, this.note});

  @override
  Widget build(BuildContext context) {
    final it = item;
    if (it == null) return const SizedBox.shrink();
    final year = it.releaseDate.length >= 4
        ? it.releaseDate.substring(0, 4)
        : '';
    final meta = <String>[
      if (year.isNotEmpty) year,
      if (it.voteAverage > 0) '★ ${it.voteAverage.toStringAsFixed(1)}',
      it.mediaType == 'movie' ? 'Film' : 'Serie TV',
    ].join('  ·  ');
    return LayoutBuilder(
      builder: (context, bounds) {
        const vPad = 10.0;
        final scale = MediaQuery.textScalerOf(context);
        final overviewLineHeight = scale.scale(14) * 1.35;
        final metaHeight = scale.scale(14) * 1.25;
        final showOverview =
            context.watch<UiSettings>().homeOverview &&
            it.overview.trim().isNotEmpty;
        final overviewLines = bounds.maxHeight >= 250 ? 3 : 2;
        final textBlock =
            6 +
            metaHeight +
            (note != null ? 6 + metaHeight : 0) +
            (showOverview ? 8 + overviewLines * overviewLineHeight : 0);
        final logoH = (bounds.maxHeight - vPad * 2 - textBlock)
            .clamp(0.0, 100.0)
            .toDouble();
        return Container(
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(16, vPad, 24, vPad),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.60,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HomeTitleArt(item: it, height: logoH),
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (showOverview) ...[
                    const SizedBox(height: 8),
                    Text(
                      it.overview,
                      maxLines: overviewLines,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
