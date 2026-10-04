import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';

/// A watch-history entry paired with the channel it belongs to.
typedef ResumeItem = (HistoryEntry, Channel);

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final discover = context.read<DiscoverProvider>();
      if (!discover.hasData) discover.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final discover = context.watch<DiscoverProvider>();
    final history = context.watch<HistoryProvider>();
    final watched = history.entries
        .map((e) => app.channelById(e.contentId))
        .whereType<Channel>()
        .toList();
    // Resolve each started item to its playlist channel; when the channel is
    // not indexed (e.g. series episodes after a restart) rebuild it from the
    // history entry itself, which stores url, title and poster.
    final started = <ResumeItem>[
      for (final e in history.continueWatching)
        if (app.channelById(e.contentId) ??
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
                        seriesName:
                            e.seriesName.isEmpty ? null : e.seriesName,
                      ))
            case final c?)
          (e, c),
    ];
    final startedMovies = <ResumeItem>[
      for (final it in started)
        if (it.$1.type == ContentType.movie) it,
    ];
    final startedSeries = <ResumeItem>[
      for (final it in started)
        if (it.$1.type == ContentType.series || it.$1.type == ContentType.anime)
          it,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DiscoverProvider>().loadForYou(watched);
    });

    if (discover.error != null && !discover.hasData) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Catalogo non disponibile',
        message: discover.error!,
        action: ElevatedButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Riprova'),
          onPressed: discover.load,
        ),
      );
    }

    if (!discover.hasData) return const _DiscoverSkeleton();

    // Only titles that can actually be watched with the playlist.
    List<TmdbItem> available(List<TmdbItem> items) =>
        items.where(app.isAvailable).take(10).toList();
    final topMovies = available(discover.topMovies);
    final topSeries = available(discover.topSeries);
    final banner = [...topMovies.take(6), ...topSeries.take(4)];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: discover.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (banner.isNotEmpty) _Top10Banner(items: banner),
          if (startedMovies.isNotEmpty) ...[
            SectionHeader(
              title: 'Film che stai guardando',
              leading: Icon(Icons.movie_outlined,
                  color: AppColors.primary, size: 20),
            ),
            _HistoryRow(items: startedMovies),
          ],
          if (startedSeries.isNotEmpty) ...[
            const SectionHeader(
              title: 'Serie TV che stai guardando',
              leading: Icon(Icons.video_library_outlined,
                  color: AppColors.secondary, size: 20),
            ),
            _HistoryRow(items: startedSeries),
          ],
          if (discover.forYou.where(app.isAvailable).isNotEmpty) ...[
            SectionHeader(
              title: 'Consigliati per te',
              subtitle: 'Perché hai guardato ${discover.forYouSource}',
              leading: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.secondary, size: 20),
            ),
            _PosterRow(items: discover.forYou.where(app.isAvailable).toList()),
          ],
          _TopSection(
            title: 'Top 10 della settimana',
            subtitle: 'In tendenza e disponibili nella tua playlist',
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
                      strokeWidth: 2, color: AppColors.primary),
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
                          blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2)),
                      if (widget.subtitle != null)
                        Text(widget.subtitle!,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
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
                    _segment('Film', !showSeries,
                        () => setState(() => _showSeries = false)),
                    _segment('Serie TV', showSeries,
                        () => setState(() => _showSeries = true)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _RankedRow(
                key: ValueKey('${widget.title}_$showSeries'), items: items),
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
      if (!mounted || widget.items.isEmpty) return;
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
          aspectRatio: 4 / 3.4,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _BannerSlide(
              item: widget.items[i],
              rank: i + 1,
            ),
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
                colors: [Colors.transparent, Color(0xCC09090D), AppColors.background],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
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
                            horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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

  const _HistoryRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return HorizontalRow(
      height: 200,
      itemCount: items.length,
      itemBuilder: (context, i) => _HistoryCard(item: items[i]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ResumeItem item;

  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final (entry, channel) = item;
    final progress = entry.duration > Duration.zero
        ? (entry.position.inSeconds / entry.duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final isEpisode = entry.type != ContentType.movie;
    final app = context.read<AppProvider>();
    final seriesKey =
        channel.seriesKey ?? (entry.seriesKey.isEmpty ? null : entry.seriesKey);
    final folder = isEpisode && seriesKey != null
        ? app.seriesFolderFor(seriesKey)
        : null;
    // Series show the standard series poster, not the episode still.
    final poster = [
      if (isEpisode) folder?.logo ?? '',
      if (isEpisode) entry.seriesPoster,
      channel.logo,
      entry.posterUrl,
    ].firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final seriesName = folder?.displaySeriesName ??
        (entry.seriesName.isNotEmpty ? entry.seriesName : null);
    final code = channel.season != null && channel.episode != null
        ? ' · S${channel.season} E${channel.episode}'
        : '';
    final title = isEpisode && seriesName != null
        ? '$seriesName$code'
        : channel.name;
    final playable = seriesKey != null && channel.seriesKey == null
        ? channel.copyWith(seriesKey: seriesKey)
        : channel;
    // Resume the exact movie/episode from where it was left.
    return Pressable(
      onTap: () =>
          playChannel(context, playable, startAt: entry.resumePosition ?? entry.position),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: poster),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.black45,
                        valueColor: AlwaysStoppedAnimation(
                            AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  final List<TmdbItem> items;

  const _PosterRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return HorizontalRow(
      height: 210,
      itemCount: items.length,
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
      height: 180,
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
          Row(children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(child: block(double.infinity, 170)),
              if (i < 2) const SizedBox(width: 12),
            ],
          ]),
        ],
      ],
    );
  }
}
