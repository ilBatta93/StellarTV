import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../models/rating_policy.dart';
import '../providers/app_provider.dart';
import '../services/imdb_rating_service.dart';
import '../services/catalog_rating_service.dart';
import '../services/title_metadata_store.dart';
import '../models/episode_metadata.dart';
import '../services/platform_catalog_service.dart';
import '../services/title_providers_service.dart';
import '../theme/app_theme.dart';

/// TMDB genres (Italian labels). Movie and TV ids differ for a few genres.
const movieGenreNames = <int, String>{
  28: 'Azione',
  12: 'Avventura',
  16: 'Animazione',
  35: 'Commedia',
  80: 'Crime',
  99: 'Documentario',
  18: 'Dramma',
  10751: 'Famiglia',
  14: 'Fantasy',
  36: 'Storia',
  27: 'Horror',
  10402: 'Musica',
  9648: 'Mistero',
  10749: 'Romance',
  878: 'Fantascienza',
  53: 'Thriller',
  10752: 'Guerra',
  37: 'Western',
};
const tvGenreNames = <int, String>{
  10759: 'Azione e Avventura',
  16: 'Animazione',
  35: 'Commedia',
  80: 'Crime',
  99: 'Documentario',
  18: 'Dramma',
  10751: 'Famiglia',
  10762: 'Bambini',
  9648: 'Mistero',
  10763: 'News',
  10764: 'Reality',
  10765: 'Sci-Fi e Fantasy',
  10766: 'Soap',
  10767: 'Talk show',
  10768: 'Guerra e Politica',
  37: 'Western',
};

/// Display facets of one title, computed on demand from local data only.
class TitleFacets {
  final List<String> genres;
  final List<StreamingPlatform> platforms;
  final List<String> categories;
  const TitleFacets(this.genres, this.platforms, this.categories);

  static TitleFacets of(
    AppProvider app, {
    TmdbItem? item,
    Channel? channel,
    bool includeCategories = true,
  }) {
    final c =
        channel ??
        (item == null ? null : app.findChannelFor(item, wait: false));
    final movie = item?.isMovie ?? c?.type == ContentType.movie;
    final names = movie ? movieGenreNames : tvGenreNames;
    final genres = <String>[
      for (final id in (c == null ? null : app.genresOf(c)) ?? const <int>[])
        if (names[id] != null) names[id]!,
    ];
    final service = PlatformCatalogService.instance;
    // Per-title official availability wins; catalog membership is used
    // only until the title's own answer is saved on the device.
    final verified = item == null
        ? null
        : TitleProvidersService.instance.platformsOf(item);
    final platforms =
        verified ??
        <StreamingPlatform>[
          for (final p in StreamingPlatform.all)
            if (item != null &&
                service.containsTitle(p, movies: movie, id: item.id))
              p,
        ];
    return TitleFacets(
      genres.take(3).toList(),
      platforms,
      c == null || !includeCategories ? const [] : app.titleCategoriesOf(c),
    );
  }
}

/// Official platform name logo on a light pill (logos are drawn for light
/// backgrounds, so every brand stays readable on the dark UI).
class PlatformBadge extends StatelessWidget {
  final StreamingPlatform platform;
  final double height;
  const PlatformBadge(this.platform, {super.key, this.height = 22});
  @override
  Widget build(BuildContext context) => Semantics(
    label: platform.name,
    child: Container(
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: height * 0.3,
        vertical: height * 0.14,
      ),
      decoration: BoxDecoration(
        color: AppColors.badgeLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Image.asset(
        platform.logoAsset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Text(
          platform.name,
          style: TextStyle(
            color: platform.color,
            fontSize: height * 0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// Official IMDb badge with the IMDb rating; TMDB vote as fallback while
/// IMDb has confirmed no rating; unknown ratings stay hidden.
class RatingValue extends StatelessWidget {
  final double? imdb;
  final double fallback;
  final double height;
  final bool framed;
  const RatingValue({
    super.key,
    this.imdb,
    this.fallback = 0,
    this.height = 20,
    this.framed = false,
  });
  @override
  Widget build(BuildContext context) {
    final rating = imdb;
    final hasImdb = rating != null && rating > 0;
    final value = preferredRating(rating, fallback);
    if (value <= 0) return const SizedBox.shrink();
    final badge = Semantics(
      label: '${hasImdb ? 'IMDb' : 'TMDB'} ${value.toStringAsFixed(1)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImdb)
            Image.asset(
              'assets/platforms/imdb.png',
              height: height,
              filterQuality: FilterQuality.medium,
            )
          else
            Icon(
              Icons.star_rounded,
              color: AppColors.secondary,
              size: height * 0.8,
            ),
          const SizedBox(width: 4),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: height * 0.65,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (!framed) return badge;
    // Same translucent dark pill as Home posters: legible on light artwork.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.overlayControl,
        borderRadius: BorderRadius.circular(6),
      ),
      child: badge,
    );
  }
}

class ImdbRatingBadge extends StatelessWidget {
  final TmdbItem item;
  final double height;
  const ImdbRatingBadge(this.item, {super.key, this.height = 20});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ImdbRatingService.instance.store,
    builder: (_, __) => RatingValue(
      imdb: ImdbRatingService.instance.ratingOf(item),
      fallback: item.voteAverage,
      height: height,
    ),
  );
}

/// All catalog layouts resolve the same identity and update only this badge.
class ChannelRatingBadge extends StatefulWidget {
  final Channel channel;
  final double height;
  final bool framed;
  const ChannelRatingBadge(
    this.channel, {
    super.key,
    this.height = 16,
    this.framed = false,
  });
  @override
  State<ChannelRatingBadge> createState() => _ChannelRatingBadgeState();
}

class _ChannelRatingBadgeState extends State<ChannelRatingBadge> {
  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(covariant ChannelRatingBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) _request();
  }

  void _request() {
    if (!TitleMetadataStore.disabled)
      CatalogRatingService.instance.request([widget.channel], priority: true);
  }

  @override
  Widget build(BuildContext context) {
    final service = CatalogRatingService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        service,
        service.identities,
        ImdbRatingService.instance.store,
      ]),
      builder: (_, __) {
        final item = service.itemOf(widget.channel);
        return RatingValue(
          imdb: item == null ? null : ImdbRatingService.instance.ratingOf(item),
          fallback: service.ratingOf(widget.channel) ?? item?.voteAverage ?? 0,
          height: widget.height,
          framed: widget.framed,
        );
      },
    );
  }
}

class EpisodeRatingBadge extends StatelessWidget {
  final EpisodeMetadata metadata;
  final bool request;
  const EpisodeRatingBadge(this.metadata, {super.key, this.request = true});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ImdbRatingService.instance.store,
    builder: (_, __) => RatingValue(
      imdb: ImdbRatingService.instance.episodeRating(
        metadata.seriesId,
        metadata.season,
        metadata.episode,
        request: request,
      ),
      fallback: metadata.tmdbRating,
      height: 16,
    ),
  );
}

/// Genres, platforms and the "also in" categories for title pages.
class TitleFacetsRow extends StatelessWidget {
  final TmdbItem? item;
  final Channel? channel;
  const TitleFacetsRow({super.key, this.item, this.channel});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        TitleProvidersService.instance.store,
        PlatformCatalogService.instance,
      ]),
      builder: (context, _) => _build(app),
    );
  }

  Widget _build(AppProvider app) {
    final f = TitleFacets.of(app, item: item, channel: channel);
    Widget chip(String label) => Container(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (f.genres.isNotEmpty || f.platforms.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in f.genres) chip(g),
                for (final p in f.platforms) PlatformBadge(p),
              ],
            ),
          ),
        if (f.categories.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Presente in ${f.categories.length} categorie: '
              '${f.categories.join(' · ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
