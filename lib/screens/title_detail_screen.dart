import 'dart:async';

import '../widgets/ui_scale.dart';
import '../services/catalog_rating_service.dart';
import '../services/segment_library.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/tmdb_item.dart';
import '../models/tmdb_person.dart';
import '../models/title_credits.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/history_provider.dart';
import '../services/catalog_builder.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/home_art.dart';
import '../widgets/section_row.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_detail_backdrop.dart';
import '../widgets/download_button.dart';
import '../services/external_player_service.dart';
import '../widgets/external_player_picker.dart';
import '../widgets/reaction_buttons.dart';
import '../widgets/trailer_button.dart';
import '../services/download_service.dart';
import '../services/title_matching.dart';
import '../services/title_versions.dart';
import '../widgets/tv_wrap_navigation.dart';
import '../widgets/category_assign_button.dart';
import '../widgets/title_facets.dart';
import '../widgets/version_picker.dart';
import '../widgets/cast_row.dart';
import '../widgets/title_credits_line.dart';
import '../widgets/track_language_badges.dart';
import '../services/title_tracks_service.dart';

double _phoneBackdropHeight(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height * 0.32;
  if (height < 168) return 168;
  if (height > 220) return 220;
  return height;
}

class TitleDetailScreen extends StatefulWidget {
  final TmdbItem? item;
  final Channel? channel;

  const TitleDetailScreen({super.key, this.item, this.channel})
    : assert(item != null || channel != null);

  @override
  State<TitleDetailScreen> createState() => _TitleDetailScreenState();
}

class _TitleDetailScreenState extends State<TitleDetailScreen> {
  TmdbItem? _item;
  List<TmdbItem> _similar = [];
  List<TmdbPerson> _cast = [];
  List<TmdbPerson> _directors = [];
  TitleInfo _info = TitleInfo.empty;
  bool _loading = true;
  String? _error;

  /// Version picked on this page; otherwise [TitleVersions] decides.
  String? _versionId;

  @override
  void initState() {
    super.initState();
    TitleVersions.instance.addListener(_versionsChanged);
    unawaited(TitleVersions.instance.load());
    final channel = widget.channel;
    _item =
        widget.item ??
        (channel == null
            ? null
            : CatalogRatingService.instance.itemOf(channel));
    _load();
  }

  Future<void> _load() async {
    final tmdb = context.read<DiscoverProvider>().tmdb;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var item = _item;
      final channel = widget.channel;
      if (item == null && channel != null) {
        await CatalogRatingService.instance.ensureLoaded();
        item = CatalogRatingService.instance.itemOf(channel);
        if (item == null) {
          final link = CatalogRatingService.instance.linkedIdentity(channel);
          item = link == null
              ? null
              : await tmdb.itemById(link.id, movie: link.movie);
          item ??= await tmdb.findByTitle(
            channel.name,
            isMovie: channel.type == ContentType.movie,
          );
        }
        // Series always use the combined page with seasons and episodes.
        if (channel.type == ContentType.series ||
            channel.type == ContentType.anime) {
          if (!mounted) return;
          openSeries(context, channel, item: item, replace: true);
          return;
        }
      }
      if (!mounted) return;
      setState(() => _item = item);
      final resolvedChannel = widget.channel;
      if (item != null && resolvedChannel != null) {
        CatalogRatingService.instance.remember(resolvedChannel, item);
      }
      if (item != null && item.isMovie) {
        SegmentLibrary.instance.prepareMovie(
          tmdbId: item.id,
          title: item.title,
        );
      }
      if (item == null) {
        setState(() => _loading = false);
        return;
      }
      // Independent lookups: run them together instead of one after another.
      final creditsFuture = tmdb.credits(item);
      final infoFuture = tmdb.details(item);
      final similar = await tmdb.recommendations(item);
      final credits = await creditsFuture;
      final info = await infoFuture;
      if (!mounted) return;
      setState(() {
        _item = item;
        _similar = similar.take(20).toList();
        _cast = credits.cast.take(20).toList();
        _directors = credits.directors;
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _versionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TitleVersions.instance.removeListener(_versionsChanged);
    super.dispose();
  }

  Channel _version(List<Channel> versions, HistoryProvider history) {
    if (versions.length == 1) return versions.first;
    final picked = versions.where((c) => c.id == _versionId).firstOrNull;
    if (picked != null) return picked;
    final started = versions
        .where((c) => history.entryFor(c.id)?.startedRemainingMinutes != null)
        .firstOrNull;
    return TitleVersions.instance.pick(versions, startedId: started?.id);
  }

  Future<void> _pickVersion(List<Channel> versions, Channel current) async {
    final picked = await showVersionPicker(
      context,
      versions: versions,
      currentId: current.id,
      title: _item?.title,
      labelOf: TitleVersions.labelOf,
    );
    if (picked != null) _selectVersion(picked);
  }

  void _selectVersion(Channel version) {
    setState(() => _versionId = version.id);
    unawaited(TitleVersions.instance.choose(version));
  }

  @override
  Widget build(BuildContext context) => UiScale(builder: _buildContent);

  Widget _buildContent(BuildContext context) {
    final app = context.watch<AppProvider>();
    final item = _item;
    // A title opened from the playlist plays that item or another copy of
    // the same film (quality versions); the TMDB lookup only adds poster,
    // plot and cast.
    final opened =
        widget.channel ?? (item == null ? null : app.findChannelFor(item));
    final variants = opened == null
        ? const <Channel>[]
        : app.movieVersions(opened);
    final playable = opened == null
        ? null
        : _version(variants, context.watch<HistoryProvider>());
    final title = item?.title ?? widget.channel!.name;
    final image = item?.backdropUrl ?? widget.channel?.logo;

    final scroll = CustomScrollView(
      // TV: keep every section built so the remote can always move back
      // up to "Guarda ora", even after scrolling far down.
      scrollCacheExtent: DeviceTypeService.isTv
          ? ScrollCacheExtent.pixels(1200)
          : null,
      slivers: [
        if (DeviceTypeService.isTv)
          SliverToBoxAdapter(
            child: SizedBox(height: TvDetailBackdrop.topSpace(context)),
          )
        else
          SliverAppBar(
            // TV: no pinned bar with a back arrow above the content (Back is
            // on the remote); going up always lands on "Guarda ora".
            pinned: true,
            automaticallyImplyLeading: true,
            expandedHeight: _phoneBackdropHeight(context),
            backgroundColor: AppColors.background,
            actions: [
              if (playable != null && !DeviceTypeService.isTv)
                IconButton(
                  tooltip: 'Preferiti',
                  icon: Icon(
                    app.favoriteIds.contains(playable.id)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: app.favoriteIds.contains(playable.id)
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  onPressed: () => app.toggleFavorite(playable),
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
                // Official title logo when TMDB has one, clean text otherwise.
                if (item != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: HomeTitleArt(
                      item: item,
                      height: DeviceTypeService.isTv ? null : 56,
                    ),
                  )
                else
                  Text(
                    displayTitle(title),
                    maxLines: DeviceTypeService.isTv ? null : 3,
                    overflow: DeviceTypeService.isTv
                        ? null
                        : TextOverflow.ellipsis,
                    style: DeviceTypeService.isTv
                        ? Theme.of(context).textTheme.headlineMedium
                        : Theme.of(context).textTheme.titleLarge,
                  ),
                const SizedBox(height: 8),
                _Meta(
                  item: item,
                  channel: widget.channel == null ? null : playable,
                ),
                if (playable != null)
                  TrackLanguageBadges(
                    // Asked once the TMDB match is settled: its id gives a
                    // surer lookup than the catalog name.
                    key: ValueKey('${playable.id}:${item?.id}:$_loading'),
                    ids: [playable.id],
                    online: _loading
                        ? null
                        : () => TitleTracksService.instance.checkTitle(
                            playable,
                            movie: item?.isMovie ?? true,
                            tmdbId: item?.id,
                            title: item?.title ?? playable.name,
                          ),
                  ),
                TitleCreditsLine(
                  directors: _directors,
                  info: _info,
                  movie: item?.isMovie ?? true,
                  title: item?.title,
                ),
                TitleFacetsRow(item: item, channel: widget.channel ?? playable),
                const SizedBox(height: 16),
                _Actions(
                  item: item,
                  playable: playable,
                  variants: variants,
                  onVersion: _selectVersion,
                  onPickVersion: () => _pickVersion(variants, playable!),
                ),
                if (item != null && item.overview.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  TitlePlot(plot: item.overview, tagline: _info.tagline),
                ],
              ],
            ),
          ),
        ),
        if (item != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ReactionButtons(item: item),
            ),
          ),
        SliverToBoxAdapter(
          child: CastRow(
            title: _directors.isEmpty ? 'Cast' : 'Regia e cast',
            cast: [
              ..._directors,
              for (final person in _cast)
                if (!_directors.any((d) => d.id == person.id)) person,
            ],
          ),
        ),
        SliverToBoxAdapter(child: _buildSimilar()),
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                32 +
                (DeviceTypeService.isTv
                    ? 0
                    : MediaQuery.paddingOf(context).bottom),
          ),
        ),
      ],
    );
    if (DeviceTypeService.isTv) {
      return TvDetailBackdrop(image: image, child: scroll);
    }
    return Scaffold(body: scroll);
  }

  Widget _buildSimilar() {
    if (_loading) {
      return Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: AppColors.warning,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Riprova')),
          ],
        ),
      );
    }
    final similar = _similar
        .where(context.watch<AppProvider>().isTmdbAllowed)
        .toList();
    if (similar.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Titoli simili',
          subtitle: 'Potrebbero piacerti anche',
        ),
        HorizontalRow(
          height: tmdbPosterRowHeight(context),
          itemCount: similar.length,
          itemBuilder: (context, i) => TmdbPosterCard(
            item: similar[i],
            onTap: () => openTmdbItem(context, similar[i]),
          ),
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  final TmdbItem? item;
  final Channel? channel;

  const _Meta({required this.item, required this.channel});

  @override
  Widget build(BuildContext context) {
    final isMovie = item?.isMovie ?? channel?.type == ContentType.movie;
    final quality = channel == null
        ? null
        : CatalogBuilder.qualityLabel(channel!.name);
    final chips = <Widget>[
      _Chip(label: isMovie ? 'Film' : 'Serie TV'),
      if (item != null && item!.year.isNotEmpty) _Chip(label: item!.year),
      if (item != null) ImdbRatingBadge(item!, priority: true),
      if (quality != null) _Chip(label: quality),
      // TV: the facets row already lists every category of the title.
      if (channel != null &&
          !(DeviceTypeService.isTv &&
              TitleFacets.of(
                    context.read<AppProvider>(),
                    item: item,
                    channel: channel,
                  ).categories.length >
                  1))
        _Chip(label: channel!.group),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
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

class _Actions extends StatelessWidget {
  final TmdbItem? item;
  final Channel? playable;
  final List<Channel> variants;
  final ValueChanged<Channel> onVersion;
  final VoidCallback onPickVersion;

  const _Actions({
    required this.item,
    required this.playable,
    required this.variants,
    required this.onVersion,
    required this.onPickVersion,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final history = context.watch<HistoryProvider>();
    final channel = playable;
    final remaining = channel == null
        ? null
        : history.entryFor(channel.id)?.startedRemainingMinutes;
    final playLabel = remaining == null
        ? 'Guarda ora'
        : 'Guarda ora · $remaining min rim.';
    final inList = item != null && app.isTmdbFavorite(item!);
    if (DeviceTypeService.isTv) return _tvActions(context, app, playLabel);
    final compact = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: AppColors.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (playable != null)
          SizedBox(
            width: double.infinity,
            child: TvFocusable(
              onPressed: () => _play(context),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(playLabel, textAlign: TextAlign.center),
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onPressed: () => _play(context),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Questo contenuto non è disponibile sul dispositivo.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (playable != null &&
                playable!.type == ContentType.movie &&
                DownloadService.canDownload(playable!))
              DownloadButton(channel: playable!, expanded: true),
            if (playable case final movie? when movie.type == ContentType.movie)
              ExternalPlayButton(
                channel: movie,
                style: compact,
                onPlay: (app) =>
                    _play(context, external: app != null, app: app),
              ),
            if (item case final trailerItem?) TrailerButton(item: trailerItem),
            if (playable case final assignable?)
              CategoryAssignButton(item: assignable),
            if (item != null)
              TvFocusable(
                onPressed: () => app.toggleTmdbFavorite(item!),
                child: OutlinedButton.icon(
                  icon: Icon(inList ? Icons.check_rounded : Icons.add_rounded),
                  label: Text(inList ? 'Nella mia lista' : 'La mia lista'),
                  style: compact.copyWith(
                    foregroundColor: WidgetStatePropertyAll(
                      inList ? AppColors.success : AppColors.textPrimary,
                    ),
                    side: WidgetStatePropertyAll(
                      BorderSide(
                        color: inList ? AppColors.success : AppColors.border,
                      ),
                    ),
                  ),
                  onPressed: () => app.toggleTmdbFavorite(item!),
                ),
              ),
          ],
        ),
        if (variants.length > 1) ...[
          const SizedBox(height: 8),
          const Text(
            'Versioni disponibili',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TvWrapNavigation(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in variants)
                  ChoiceChip(
                    label: Text(
                      v.group != playable!.group
                          ? '${TitleVersions.labelOf(v)} · ${v.group}'
                          : TitleVersions.labelOf(v),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: v.id == playable!.id,
                    onSelected: (_) => onVersion(v),
                  ),
              ],
            ),
          ),
        ],
        if (DeviceTypeService.isTv && playable != null) ...[
          const SizedBox(height: 8),
          TvFocusable(
            onPressed: () => app.toggleFavorite(playable!),
            child: OutlinedButton.icon(
              icon: Icon(
                app.favoriteIds.contains(playable!.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: app.favoriteIds.contains(playable!.id)
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
              label: Text(
                app.favoriteIds.contains(playable!.id)
                    ? 'Nei preferiti'
                    : 'Aggiungi ai preferiti',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => app.toggleFavorite(playable!),
            ),
          ),
        ],
        if (playable != null && playable!.type != ContentType.live) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Disponibile sul dispositivo: ${playable!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tvActions(BuildContext context, AppProvider app, String playLabel) {
    final channel = playable;
    final titleItem = item;
    final inList = titleItem != null && app.isTmdbFavorite(titleItem);
    return TvWrapNavigation(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (channel != null) ...[
            TvFocusable(
              autofocus: true,
              onPressed: () => _play(context),
              child: ElevatedButton.icon(
                onPressed: () => _play(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(playLabel, textAlign: TextAlign.center),
              ),
            ),
            TvFocusable(
              onPressed: () => app.toggleFavorite(channel),
              child: OutlinedButton.icon(
                onPressed: () => app.toggleFavorite(channel),
                icon: Icon(
                  app.favoriteIds.contains(channel.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                label: Text(
                  app.favoriteIds.contains(channel.id)
                      ? 'Nei preferiti'
                      : 'Preferiti',
                ),
              ),
            ),
            if (variants.length > 1)
              TvFocusable(
                onPressed: onPickVersion,
                child: OutlinedButton.icon(
                  onPressed: onPickVersion,
                  icon: const Icon(Icons.high_quality_rounded),
                  label: Text('Versione: ${TitleVersions.labelOf(channel)}'),
                ),
              ),
            if (channel.type == ContentType.movie)
              ExternalPlayButton(
                channel: channel,
                onPlay: (app) =>
                    _play(context, external: app != null, app: app),
              ),
            if (DownloadService.canDownload(channel))
              DownloadButton(channel: channel, expanded: true),
          ],
          if (titleItem != null) ...[
            TvFocusable(
              autofocus: channel == null,
              onPressed: () => app.toggleTmdbFavorite(titleItem),
              child: OutlinedButton.icon(
                onPressed: () => app.toggleTmdbFavorite(titleItem),
                icon: Icon(inList ? Icons.check_rounded : Icons.add_rounded),
                label: Text(inList ? 'Nella mia lista' : 'La mia lista'),
              ),
            ),
            TrailerButton(item: titleItem),
          ],
        ],
      ),
    );
  }

  /// [external] as in [playChannel]; [app] is the one-off "Apri con" pick.
  Future<void> _play(
    BuildContext context, {
    bool? external,
    ExternalPlayer? app,
  }) async {
    if (playable == null) return;
    final entry = CatalogEntry(
      primary: playable!,
      variants: variants.isEmpty ? [playable!] : variants,
    );
    final channel = entry.primary;
    if (channel.type == ContentType.series ||
        channel.type == ContentType.anime) {
      openSeries(context, channel, item: item);
      return;
    }
    playChannel(
      context,
      channel,
      startAt: _resumeFor(context, channel),
      external: external,
      externalApp: app,
    );
  }

  Duration? _resumeFor(BuildContext context, Channel channel) {
    final entry = context.read<HistoryProvider>().entryFor(channel.id);
    return entry?.resumePosition;
  }
}
