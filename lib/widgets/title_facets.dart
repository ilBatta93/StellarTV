import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/streaming_platform.dart';
import '../models/tmdb_item.dart';
import '../providers/app_provider.dart';
import '../services/platform_catalog_service.dart';
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
    final platforms = <StreamingPlatform>[
      for (final p in StreamingPlatform.all)
        if ((item != null &&
                service.containsTitle(p, movies: movie, id: item.id)) ||
            (c != null && (p.tagMatches(c.group) || p.tagMatches(c.name))))
          p,
    ];
    return TitleFacets(
      genres.take(3).toList(),
      platforms,
      c == null || !includeCategories ? const [] : app.titleCategoriesOf(c),
    );
  }
}

/// Small brand-coloured platform label.
class PlatformBadge extends StatelessWidget {
  final StreamingPlatform platform;
  const PlatformBadge(this.platform, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: platform.color.withValues(alpha: 0.2),
      border: Border.all(color: platform.color.withValues(alpha: 0.75)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      platform.name,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
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
