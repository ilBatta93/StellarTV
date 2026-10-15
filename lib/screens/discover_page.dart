import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../widgets/expiry_banner.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/history_entry.dart';
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
    final reactions = context.watch<ReactionsProvider>();
    // Episodes may not be indexed after a restart: rebuild them from the
    // history entry so watched series still feed "Serie consigliate".
    final watched = history.entries
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
          if (!app.kidsMode || app.isKidsContent(c)) (e, c),
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
      if (mounted)
        context.read<DiscoverProvider>().loadForYou(
          watched,
          liked: reactions.liked.where(app.isTmdbAllowed).toList(),
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
        initialHistory: latestHistoryResume(history.entries, app),
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
            'In tendenza e disponibili nella tua playlist',
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
              title: 'Consigliati per te',
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
      height: tv ? tmdbPosterRowHeight(context) + 4 : 200,
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
    final seriesName =
        folder?.displaySeriesName ??
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
      onFocus: onFocus,
      onTap: () => playChannel(
        context,
        playable,
        startAt: entry.resumePosition ?? entry.position,
      ),
      child: SizedBox(
        width: DeviceTypeService.isTv ? 112 : 120,
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
                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              // TV: keep the title inside the orange focus frame.
              padding: DeviceTypeService.isTv
                  ? const EdgeInsets.fromLTRB(9, 0, 9, 9)
                  : EdgeInsets.zero,
              child: DeviceTypeService.isTv
                  ? TvPosterTitle(title)
                  : Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: DeviceTypeService.isTv ? 14 : 13,
                        fontWeight: DeviceTypeService.isTv
                            ? FontWeight.w700
                            : FontWeight.w600,
                        height: 1.2,
                      ),
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
      height: tmdbPosterRowHeight(context),
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
  final offset = viewport.getOffsetToReveal(target, 0).offset;
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
    super.dispose();
  }

  // Debounced so scrolling quickly with the remote does not load every
  // backdrop on the way.
  void _focus(TmdbItem item) {
    _userFocused = true;
    _heroRequest++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _hero.value = item;
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
    _debounce = Timer(
      initial ? Duration.zero : const Duration(milliseconds: 220),
      () async {
        final item = _historyInfo.containsKey(key)
            ? _historyInfo[key]
            : await tmdb
                  .findByTitle(title, isMovie: movie)
                  .catchError((_) => null);
        if (!mounted || request != _heroRequest) return;
        _historyInfo[key] = item;
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
      },
    );
  }

  void _revealHeading(BuildContext rowContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !rowContext.mounted) return;
      _revealTvHeading(rowContext);
    });
  }

  Widget _historySection(String title, List<ResumeItem> items) => Builder(
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

  Widget _row(String title, List<TmdbItem> items) {
    return Builder(
      builder: (rowContext) => _posterRow(title, items, rowContext),
    );
  }

  Widget _posterRow(
    String title,
    List<TmdbItem> items,
    BuildContext rowContext,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TvRowTitle(title),
        HorizontalRow(
          // Poster + two full title lines + focus frame, never clipped.
          height: tmdbPosterRowHeight(context, mobile: 212),
          spacing: 20,
          itemCount: items.length,
          itemBuilder: (context, i) => TmdbPosterCard(
            item: items[i],
            onTap: () => openTmdbItem(context, items[i]),
            onFocus: () {
              _focus(items[i]);
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
        final heroHeight = (c.maxHeight * 0.36).clamp(210.0, 260.0);
        return Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<TmdbItem?>(
                valueListenable: _hero,
                builder: (_, item, _) => _TvHeroBackdrop(item: item),
              ),
            ),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: heroHeight,
                  child: ValueListenableBuilder<TmdbItem?>(
                    valueListenable: _hero,
                    builder: (_, item, _) => _TvHeroInfo(item: item),
                  ),
                ),
                Expanded(
                  child: ListView(
                    // Rows are pre-built so pressing Down always finds the
                    // next row instead of stopping on unbuilt content.
                    cacheExtent: 2400,
                    padding: const EdgeInsets.only(top: 12, bottom: 48),
                    children: [
                      const ExpiryBanner(),
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
                          widget.forYouSource == null
                              ? 'Consigliati per te'
                              : 'Consigliati per te · perché hai guardato '
                                    '${widget.forYouSource}',
                          widget.forYou,
                        ),
                      if (widget.forYouSeries.isNotEmpty)
                        _row(
                          widget.forYouSeriesSource == null
                              ? 'Serie consigliate per te'
                              : 'Serie consigliate per te · perché hai '
                                    'guardato ${widget.forYouSeriesSource}',
                          widget.forYouSeries,
                        ),
                      for (final t in widget.tops)
                        _TvTopRow(spec: t, onFocusItem: _focus),
                    ],
                  ),
                ),
              ],
            ),
          ],
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

  const _TvTopRow({required this.spec, required this.onFocusItem});

  @override
  State<_TvTopRow> createState() => _TvTopRowState();
}

class _TvTopRowState extends State<_TvTopRow> {
  bool _showSeries = false;
  final _headingKey = GlobalKey();
  final _movieFocus = FocusNode(debugLabel: 'top movies');
  final _seriesFocus = FocusNode(debugLabel: 'top series');
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
    return Column(
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
              if (hasMovies && hasSeries) ...[
                const SizedBox(width: 24),
                _chip('Film', _movieFocus, !showSeries, () {
                  setState(() => _showSeries = false);
                }),
                const SizedBox(width: 12),
                _chip('Serie TV', _seriesFocus, showSeries, () {
                  setState(() => _showSeries = true);
                }),
              ],
            ],
          ),
        ),
        HorizontalRow(
          key: ValueKey('${title}_$showSeries'),
          height: 204,
          spacing: 16,
          itemCount: items.length,
          itemBuilder: (context, i) => Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (hasMovies &&
                  hasSeries &&
                  event.logicalKey == LogicalKeyboardKey.arrowUp) {
                if (event is KeyDownEvent)
                  (showSeries ? _seriesFocus : _movieFocus).requestFocus();
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final heading = _headingKey.currentContext;
                  if (mounted && heading != null) _revealTvHeading(heading);
                });
              },
            ),
          ),
        ),
      ],
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
      onPressed: onTap,
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

  const _TvRowTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Sora',
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
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
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.background.withValues(alpha: 0.92),
                        AppColors.background.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.38, 0.75],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        AppColors.background,
                        AppColors.background.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.38, 0.62],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background.withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.16],
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

  const _TvHeroInfo({required this.item});

  @override
  Widget build(BuildContext context) {
    final it = item;
    if (it == null) return const SizedBox.shrink();
    Widget chip(String text) => Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.textSecondary, width: 1.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 70, 24, 8),
      child: FractionallySizedBox(
        alignment: Alignment.topLeft,
        widthFactor: 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              flex: 2,
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.5,
                    child: Text(
                      it.title,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                it.overview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                chip(it.isMovie ? 'Film' : 'Serie TV'),
                if (it.year.isNotEmpty) chip(it.year),
                if (it.voteAverage > 0)
                  chip('★ ${it.voteAverage.toStringAsFixed(1)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
