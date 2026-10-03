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
    final startedMovies = <ResumeItem>[
      for (final e in history.continueWatching)
        if (app.channelById(e.contentId) case final c? when c.type == ContentType.movie)
          (e, c),
    ];
    final startedSeries = <ResumeItem>[
      for (final e in history.continueWatching)
        if (app.channelById(e.contentId) case final c?
            when c.type == ContentType.series || c.type == ContentType.anime)
          (e, c),
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

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: discover.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (discover.topMovies.isNotEmpty) ...[
            _Top10Banner(items: discover.topMovies.take(10).toList()),
          ] else if (discover.featured != null) _Hero(item: discover.featured!),
          if (startedMovies.isNotEmpty) ...[
            const SectionHeader(
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
          if (discover.forYou.isNotEmpty) ...[
            SectionHeader(
              title: 'Consigliati per te',
              subtitle: 'Perché hai guardato ${discover.forYouSource}',
              leading: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.secondary, size: 20),
            ),
            _PosterRow(items: discover.forYou),
          ],
          const SectionHeader(title: 'Top 10 Film', subtitle: 'I più visti questa settimana'),
          _RankedRow(items: discover.topMovies),
          const SectionHeader(title: 'Top 10 Serie TV', subtitle: 'Le più viste questa settimana'),
          _RankedRow(items: discover.topSeries),
          for (final p in StreamingPlatform.all)
            if (discover.platformTop(p).isNotEmpty) ...[
              SectionHeader(
                title: 'Top 10 su ${p.name}',
                leading: Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: p.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _RankedRow(items: discover.platformTop(p)),
            ],
          if (discover.isLoading)
            const Padding(
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

class _Hero extends StatelessWidget {
  final TmdbItem item;

  const _Hero({required this.item});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final match = app.findChannelFor(item);
    return Pressable(
      onTap: () => openTmdbItem(context, item),
      child: AspectRatio(
        aspectRatio: 4 / 3.4,
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
                      item.isMovie ? 'FILM N.1 IN TENDENZA' : 'SERIE N.1 IN TENDENZA',
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (match != null) ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Guarda'),
                          onPressed: () => playChannel(context, match),
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
                    'FILM N.$rank IN TENDENZA',
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
                        onPressed: () => playChannel(context, match),
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
    final isSeries = channel.type == ContentType.series ||
        channel.type == ContentType.anime;
    return Pressable(
      onTap: () => isSeries
          ? openChannel(context, channel)
          : playChannel(context, channel, startAt: entry.position),
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
                    PosterImage(
                      url: channel.logo.isNotEmpty
                          ? channel.logo
                          : entry.posterUrl,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.black45,
                        valueColor: const AlwaysStoppedAnimation(
                            AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              channel.name,
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

  const _RankedRow({required this.items});

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
