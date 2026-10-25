import 'package:flutter/material.dart';

import '../services/catalog_builder.dart';
import 'title_facets.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import 'poster_card.dart';
import 'tv_focusable.dart';

/// Apple TV style wide card: the artwork fills a 16:9 tile with the title,
/// rating and quality laid over a soft gradient.
class CatalogLandscapeCard extends StatelessWidget {
  const CatalogLandscapeCard({
    super.key,
    required this.entry,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  final CatalogEntry entry;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    final channel = entry.primary;
    final quality = CatalogBuilder.qualityLabel(channel.name);
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred-looking fill plus the full poster on the left: posters
          // are vertical, so they are framed instead of cropped badly.
          if (!tv)
            Opacity(opacity: 0.35, child: PosterImage(url: channel.logo)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppColors.overlay, AppColors.background],
              ),
            ),
          ),
          Row(
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: PosterImage(url: channel.logo),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(tv ? 14 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        channel.displaySeriesName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: tv ? 17 : 14,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChannelRatingBadge(channel),
                          if (quality != null) _Chip(quality),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        channel.group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isFavorite)
            Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.favorite_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
        ],
      ),
    );
    if (tv) {
      return TvFocusable(
        borderRadius: BorderRadius.circular(14),
        onPressed: onTap,
        onLongPress: onFavoriteTap,
        child: content,
      );
    }
    return Pressable(onTap: onTap, onLongPress: onFavoriteTap, child: content);
  }
}

/// Infuse style header: big poster and details of the selected title, shown
/// above a dense grid. Follows the remote focus on TV.
class CatalogSpotlightHeader extends StatelessWidget {
  const CatalogSpotlightHeader({super.key, required this.entry});

  final CatalogEntry? entry;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    final e = entry;
    final height = tv ? 210.0 : 170.0;
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: tv ? Duration.zero : const Duration(milliseconds: 220),
        child: e == null
            ? const SizedBox.shrink()
            : _SpotlightBody(key: ValueKey(e.primary.id), entry: e, tv: tv),
      ),
    );
  }
}

class _SpotlightBody extends StatelessWidget {
  const _SpotlightBody({super.key, required this.entry, required this.tv});

  final CatalogEntry entry;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    final channel = entry.primary;
    final quality = CatalogBuilder.qualityLabel(channel.name);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!tv)
            Opacity(opacity: 0.18, child: PosterImage(url: channel.logo)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: PosterImage(url: channel.logo),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        channel.displaySeriesName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: tv ? 26 : 18,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChannelRatingBadge(channel),
                          if (quality != null) _Chip(quality),
                          if (entry.variants.length > 1)
                            _Chip('${entry.variants.length} versioni'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        channel.group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: tv ? 15 : 12,
                        ),
                      ),
                      if (tv) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'OK per aprire · tieni premuto per i preferiti',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.overlayControl,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: AppColors.primary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}
