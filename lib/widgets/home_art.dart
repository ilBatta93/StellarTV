import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tmdb_item.dart';
import '../providers/discover_provider.dart';
import '../providers/ui_settings.dart';
import '../services/device_type_service.dart';
import '../services/image_cache_service.dart';
import '../services/title_display.dart';
import '../theme/app_theme.dart';
import 'poster_card.dart';
import 'tv_home_layout.dart';

/// Same bounded presentation on TV and touch, no new focus stops.
class HomeTitleArt extends StatefulWidget {
  const HomeTitleArt({super.key, required this.item, this.height});
  final double? height;
  final TmdbItem item;
  @override
  State<HomeTitleArt> createState() => _HomeTitleArtState();
}

/// Resolves only a small adjacent set after display, never a catalog scan.
void warmTitleLogos(BuildContext context, Iterable<TmdbItem> items) {
  final tmdb = context.read<DiscoverProvider>().tmdb;
  final selected = items.take(3).toList();
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    for (final item in selected) {
      final url = await tmdb.titleLogo(item);
      if (!context.mounted) return;
      if (url != null) {
        await precacheImage(
          ResizeImage(
            CachedNetworkImageProvider(
              url,
              cacheManager: AppImageCache.manager,
            ),
            width: 640,
          ),
          context,
          onError: (_, _) {},
        );
      }
    }
  });
}

class _HomeTitleArtState extends State<HomeTitleArt> {
  Future<String?>? _logo;
  String? _key;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeTitleArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    if (_key == widget.item.key) return;
    _key = widget.item.key;
    _logo = context.read<DiscoverProvider>().tmdb.titleLogo(widget.item);
    warmTitleLogos(context, [widget.item]);
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height ?? (DeviceTypeService.isTv ? 86.0 : 72.0);
    final title = displayTitle(widget.item.title);
    final fallback = Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        key: const ValueKey('tv-home-banner-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontSize: DeviceTypeService.isTv ? 26 : 24,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FutureBuilder<String?>(
        future: _logo,
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (!context.select<UiSettings, bool>((ui) => ui.showPosters)) {
            return fallback;
          }
          // A pending lookup is not evidence that the title has no logo.
          // Never flash text (or the previous title's logo) during a swap.
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.expand();
          }
          if (url == null) return fallback;
          return Semantics(
            label: title,
            image: true,
            child: CachedNetworkImage(
              cacheManager: AppImageCache.manager,
              imageUrl: url,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              memCacheWidth: 640,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => const SizedBox.expand(),
              errorWidget: (_, _, _) => fallback,
            ),
          );
        },
      ),
    );
  }
}

double homeCardWidth([BuildContext? context]) {
  if (!DeviceTypeService.isTv) return 208;
  if (context == null) return 244;
  final layout = TvHomeLayout.maybeOf(context);
  if (layout != null) return layout.historyWidth;
  return (MediaQuery.sizeOf(context).width * 0.255).clamp(244.0, 326.0);
}

double homeRowHeight(BuildContext context) =>
    homeCardWidth(context) * 9 / 16 +
    MediaQuery.textScalerOf(context).scale(13) * 1.25 * 2 +
    34;

class HomeLandscapeCard extends StatelessWidget {
  const HomeLandscapeCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.onFocus,
    this.rank,
    this.rating,
    this.progress,
    this.trailing,
  });
  final String title;
  final String? image;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  final int? rank;
  final double? rating;
  final double? progress;

  /// Small label on the right of the title space (e.g. "S1 · E2").
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final watched = progress?.clamp(0.0, 1.0);
    final label = trailing;
    final width = homeCardWidth(context);
    return Pressable(
      onTap: onTap,
      onFocus: onFocus,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: image),
                    if (rank != null || watched != null)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppColors.overlay],
                          ),
                        ),
                      ),
                    if (rank != null)
                      Positioned(
                        left: 14,
                        bottom: 12,
                        child: Text(
                          '#$rank',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    if (rating != null && rating! > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: RatingBadge(value: rating!),
                      ),
                    if (watched != null) ...[
                      Positioned(
                        right: 10,
                        bottom: 14,
                        child: Text(
                          '${(watched * 100).round()}%',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 7,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: watched,
                            minHeight: 3,
                            color: AppColors.primary,
                            backgroundColor: AppColors.border,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      displayTitle(title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: (width - 30) * 0.42),
                      child: Align(
                        alignment: Alignment.topRight,
                        widthFactor: 1,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topRight,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves only built history tiles, preserving the provider image fallback.
class HomeHistoryArtwork extends StatefulWidget {
  const HomeHistoryArtwork({
    super.key,
    required this.title,
    required this.isMovie,
    required this.fallback,
    required this.builder,
  });
  final String title;
  final bool isMovie;
  final String fallback;
  final Widget Function(String?) builder;
  @override
  State<HomeHistoryArtwork> createState() => _HomeHistoryArtworkState();
}

class _HomeHistoryArtworkState extends State<HomeHistoryArtwork> {
  Future<TmdbItem?>? _item;
  String? _key;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeHistoryArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final key = '${widget.isMovie}:${widget.title}';
    if (_key == key) return;
    _key = key;
    _item = context.read<DiscoverProvider>().tmdb.homeArtwork(
      widget.title,
      isMovie: widget.isMovie,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TmdbItem?>(
    future: _item,
    builder: (_, snapshot) =>
        widget.builder(snapshot.data?.backdropUrl ?? widget.fallback),
  );
}
