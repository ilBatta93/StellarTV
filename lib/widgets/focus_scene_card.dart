import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/episode_metadata.dart';
import '../models/focus_scene_policy.dart';
import '../models/tmdb_item.dart';
import '../providers/app_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/history_provider.dart';
import '../providers/ui_settings.dart';
import '../services/catalog_builder.dart';
import '../services/focus_scene_service.dart';
import '../services/image_cache_service.dart';
import '../services/series_grouping.dart';
import '../services/title_runtime_store.dart';
import '../theme/app_theme.dart';
import 'banner_trailer.dart';
import 'channel_card.dart';
import 'poster_card.dart';
import 'poster_overlay.dart';
import 'title_facets.dart';

/// "Scena sulla locandina selezionata" (TV Home rows): once the remote has
/// rested on a cover for [delay], the card widens to 16:9 and shows a scene
/// still with the logo and the chosen details at the bottom left.
///
/// Scrolling fast through a row never loads anything: only the cover the
/// remote stops on resolves its scene, once (see [FocusSceneService]).
class FocusSceneHost extends StatefulWidget {
  const FocusSceneHost({
    super.key,
    required this.item,
    required this.posterHeight,
    required this.builder,
  });

  final TmdbItem item;

  /// Height of the poster picture: the scene keeps it, only the width grows.
  final double posterHeight;

  /// [scene] is null for the normal cover; otherwise it fills a picture
  /// [sceneWidth] wide in place of the poster.
  final Widget Function(BuildContext context, Widget? scene, double? sceneWidth)
  builder;

  static const delay = Duration(milliseconds: 600);

  @override
  State<FocusSceneHost> createState() => _FocusSceneHostState();
}

class _FocusSceneHostState extends State<FocusSceneHost> {
  Timer? _timer;
  bool _open = false;

  void _focusChanged(bool focused) {
    _timer?.cancel();
    if (!focused) {
      if (_open) setState(() => _open = false);
      return;
    }
    _timer = Timer(FocusSceneHost.delay, () {
      if (!mounted) return;
      setState(() => _open = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    });
  }

  /// The card grew to the right: keep its end inside the row.
  void _reveal() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final row = Scrollable.maybeOf(context);
    if (box == null || !box.attached || row == null) return;
    if (row.position.axis != Axis.horizontal) return;
    row.position.ensureVisible(
      box,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  void didUpdateWidget(covariant FocusSceneHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rows reuse cards by position: another title starts as a cover.
    if (oldWidget.item.key != widget.item.key) _open = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: _focusChanged,
    child: widget.builder(
      context,
      _open
          ? FocusSceneArt(
              key: ValueKey(widget.item.key),
              item: widget.item,
              height: widget.posterHeight,
            )
          : null,
      _open ? widget.posterHeight * 16 / 9 : null,
    ),
  );
}

/// The scene picture of a selected cover, with the logo, details, episode
/// and badges chosen in Impostazioni.
class FocusSceneArt extends StatefulWidget {
  const FocusSceneArt({super.key, required this.item, required this.height});

  final TmdbItem item;
  final double height;

  @override
  State<FocusSceneArt> createState() => _FocusSceneArtState();
}

class _FocusSceneArtState extends State<FocusSceneArt> {
  late final Channel? _match;
  late final Future<FocusScene> _scene;
  Future<String?>? _logo;

  /// "Trailer nell'immagine di scena" on the Home: this picture hosts it.
  SceneTrailerScope? _trailer;
  SceneTrailerSlot? _slot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = SceneTrailerScope.maybeOf(context);
    if (identical(scope, _trailer)) return;
    _leave();
    _trailer = scope;
    if (scope == null) return;
    final slot = _slot = SceneTrailerSlot(widget.item, context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_slot, slot)) scope.slot.value = slot;
    });
  }

  /// Hands the slot back, after the frame: the trailer layer rebuilds on
  /// the change, which cannot happen while this picture is torn down.
  void _leave() {
    final scope = _trailer;
    final slot = _slot;
    _slot = null;
    if (scope == null || slot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(scope.slot.value, slot)) scope.slot.value = null;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _match = Provider.of<AppProvider?>(
      context,
      listen: false,
    )?.findChannelFor(item);
    SceneEpisode? last;
    var lastWatched = false;
    final history = Provider.of<HistoryProvider?>(context, listen: false);
    final match = _match;
    if (!item.isMovie && match != null && history != null) {
      final entry = history.lastOfSeries(match.seriesKey ?? match.id);
      if (entry != null) {
        final parsed = SeriesGrouping.parseTitle(entry.title);
        if (parsed.season != null && parsed.episode != null) {
          last = (season: parsed.season!, episode: parsed.episode!);
          lastWatched = entry.isWatched;
        }
      }
    }
    _scene = FocusSceneService.instance.resolve(
      item,
      last: last,
      lastWatched: lastWatched,
    );
    if (context.read<UiSettings>().focusSceneLogo) {
      _logo = Provider.of<DiscoverProvider?>(
        context,
        listen: false,
      )?.tmdb.titleLogo(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    final item = widget.item;
    final match = _match;
    return FutureBuilder<FocusScene>(
      future: _scene,
      builder: (context, snapshot) {
        final scene = snapshot.data;
        // A film's still is known at once; a series waits for its episode
        // instead of flashing the series still first.
        final url = scene != null
            ? scene.imageUrl
            : item.isMovie
            ? item.sceneUrl
            : null;
        final episode = scene?.episode;
        Widget picture = Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.surface),
            if (url != null)
              PosterImage(
                url: url,
                fallbackIcon: Icons.movie_outlined,
                maxDecodeWidth: 780,
              )
            else if (scene != null)
              // No still at all: the poster, as before.
              PosterImage(url: item.posterUrl),
          ],
        );
        final trailer = _trailer;
        if (trailer != null) {
          // The trailer plays under the picture, which fades out over it;
          // logo and details stay on top.
          picture = ValueListenableBuilder<String?>(
            valueListenable: trailer.playing,
            builder: (_, playing, child) => AnimatedOpacity(
              opacity: playing == item.key ? 0 : 1,
              duration: const Duration(milliseconds: 500),
              child: child,
            ),
            child: picture,
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            picture,
            PosterOverlay(
              bottomLeft: [
                if (ui.focusSceneBadges && match != null) ...[
                  if (ui.badgeNew) PosterNewBadge(match),
                  if (ui.showQuality &&
                      CatalogBuilder.qualityLabel(match.name) != null)
                    PosterQualityBadge(
                      CatalogBuilder.qualityLabel(match.name)!,
                    ),
                  if (ui.badgePlatform) PosterPlatformBadge(match),
                ],
              ],
              caption: _caption(ui, episode),
              edge: ui.focusSceneBadges && match != null
                  ? PosterProgressMark(match, part: PosterProgressPart.bar)
                  : null,
              edgeHeight: 5,
            ),
          ],
        );
      },
    );
  }

  Widget _caption(UiSettings ui, EpisodeMetadata? episode) {
    final item = widget.item;
    final title = Text(
      item.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        height: 1.1,
        shadows: [Shadow(color: Color(0xCC000000), blurRadius: 4)],
      ),
    );
    final logoHeight = (widget.height * 0.24).clamp(28.0, 64.0);
    final minutes = TitleRuntimeStore.instance.store.valueOf(item.key);
    final details = [
      if (item.year.isNotEmpty) item.year,
      if (minutes != null && minutes > 0)
        item.isMovie ? '$minutes min' : 'ep. $minutes min',
    ].join(' · ');
    const small = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(color: Color(0xCC000000), blurRadius: 4)],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ui.focusSceneLogo) _logoOr(title, logoHeight) else title,
        if (ui.focusSceneDetails) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (details.isNotEmpty) ...[
                Flexible(
                  child: Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              RatingBadge(value: item.voteAverage, item: item, reveal: true),
            ],
          ),
        ],
        if (ui.focusSceneEpisode && episode != null) ...[
          const SizedBox(height: 3),
          Text(
            focusSceneEpisodeLabel(
              episode.season,
              episode.episode,
              episode.title,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small,
          ),
        ],
      ],
    );
  }

  /// The written title stays until the logo is there.
  Widget _logoOr(Widget title, double height) {
    final logo = _logo;
    if (logo == null) return title;
    return FutureBuilder<String?>(
      future: logo,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return title;
        return Semantics(
          label: widget.item.title,
          image: true,
          child: SizedBox(
            height: height,
            child: CachedNetworkImage(
              cacheManager: AppImageCache.manager,
              imageUrl: url,
              fit: BoxFit.contain,
              alignment: Alignment.bottomLeft,
              memCacheWidth: 480,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => title,
              errorWidget: (_, _, _) => title,
            ),
          ),
        );
      },
    );
  }
}
