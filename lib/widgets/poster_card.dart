import '../models/home_layout_preferences.dart';
import 'home_presentation.dart';
import '../services/image_cache_service.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tmdb_item.dart';
import '../providers/ui_settings.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import 'tv_focusable.dart';
import 'tv_home_layout.dart';

class PosterImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final IconData fallbackIcon;

  const PosterImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.movie_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.card,
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: AppColors.textMuted, size: 28),
    );
    // The "Mostra anteprime" setting: when off, all poster images become a
    // neutral placeholder tile.
    if (!context.watch<UiSettings>().showPosters) return fallback;
    if (url == null || url!.isEmpty) return fallback;
    // Decode images at their on-screen size: full-size decoding of every
    // poster exhausts memory on TV boxes and makes the app close.
    return LayoutBuilder(
      builder: (context, c) {
        int? cacheWidth;
        if (c.maxWidth.isFinite && c.maxWidth > 0) {
          final px = c.maxWidth * MediaQuery.devicePixelRatioOf(context);
          cacheWidth = ((px / 64).ceil() * 64).clamp(64, 1280);
        }
        return CachedNetworkImage(
          cacheManager: AppImageCache.manager,
          imageUrl: url!,
          fit: fit,
          memCacheWidth: cacheWidth,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, _) => Container(color: AppColors.card),
          errorWidget: (_, _, _) => fallback,
        );
      },
    );
  }
}

class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;

  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onFocus,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final animations = context.watch<UiSettings>().animations;
    final gesture = GestureDetector(
      onTapDown: animations ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: animations ? () => setState(() => _pressed = false) : null,
      onTapUp: animations ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: animations && _pressed ? 0.95 : 1,
        duration: animations
            ? const Duration(milliseconds: 140)
            : Duration.zero,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
    return TvFocusable(
      onPressed: widget.onTap,
      onLongPress: widget.onLongPress,
      revealOnFocus: widget.onFocus == null,
      onFocusChange: widget.onFocus == null
          ? null
          : (f) {
              if (f) widget.onFocus!();
            },
      child: gesture,
    );
  }
}

class TmdbPosterCard extends StatelessWidget {
  final TmdbItem item;
  final VoidCallback onTap;
  final double width;
  final VoidCallback? onFocus;

  const TmdbPosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 120,
    this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    final home = HomePresentation.contains(context);
    final ui = context.watch<UiSettings>();
    final ratio = home ? ui.homePosterShape.aspectRatio : 2 / 3;
    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PosterImage(
            url: home && ui.homePosterShape == HomePosterShape.landscape
                ? item.backdropUrl ?? item.posterUrl
                : item.posterUrl,
          ),
          if (item.voteAverage > 0)
            Positioned(
              top: 6,
              left: 6,
              child: RatingBadge(value: item.voteAverage),
            ),
        ],
      ),
    );
    final fillsCell = !width.isFinite;
    final effectiveWidth = home && !fillsCell
        ? HomePresentation.width(context)
        : DeviceTypeService.isTv && !fillsCell
        ? TvHomeLayout.maybeOf(context)?.posterWidth ?? 112.0
        : width;
    return Pressable(
      onTap: onTap,
      onFocus: onFocus,
      child: SizedBox(
        width: fillsCell ? null : effectiveWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fillsCell)
              Expanded(child: poster)
            else
              AspectRatio(aspectRatio: ratio, child: poster),
            if (!home || ui.homeTitles)
              Padding(
                padding: DeviceTypeService.isTv
                    ? const EdgeInsets.fromLTRB(9, 8, 9, 9)
                    : const EdgeInsets.only(top: 8),
                child: DeviceTypeService.isTv
                    ? TvPosterTitle(item.title)
                    : Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: DeviceTypeService.isTv ? 14 : 12,
                          fontWeight: DeviceTypeService.isTv
                              ? FontWeight.w700
                              : FontWeight.w600,
                          height: DeviceTypeService.isTv ? 1.2 : 1.1,
                          shadows: [
                            Shadow(
                              color: AppColors.overlay,
                              offset: const Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class RankedPosterCard extends StatelessWidget {
  final TmdbItem item;
  final int rank;
  final VoidCallback onTap;
  final VoidCallback? onFocus;

  const RankedPosterCard({
    super.key,
    required this.item,
    required this.rank,
    required this.onTap,
    this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    final home = DeviceTypeService.isTv ? TvHomeLayout.maybeOf(context) : null;
    final customized = HomePresentation.contains(context);
    final ui = context.watch<UiSettings>();
    final ratio = customized ? ui.homePosterShape.aspectRatio : 2 / 3;
    final imageWidth = customized
        ? HomePresentation.width(context, ranked: true)
        : null;
    final imageHeight = imageWidth == null ? null : imageWidth / ratio;
    final homePosterWidth =
        imageWidth ?? (home == null ? null : (home.rankedHeight - 16) * 2 / 3);
    return Pressable(
      onTap: onTap,
      onFocus: onFocus,
      child: SizedBox(
        width: homePosterWidth != null
            ? homePosterWidth + (rank >= 10 ? 72 : 50)
            : DeviceTypeService.isTv
            ? (rank >= 10 ? 184 : 158)
            : (rank >= 10 ? 196 : 172),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: DeviceTypeService.isTv ? 0 : -18,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: imageHeight != null
                      ? (imageHeight * 0.55).clamp(36.0, 140.0)
                      : home == null
                      ? (DeviceTypeService.isTv ? 100 : 128)
                      : (home.rankedHeight * 0.55).clamp(64.0, 140.0),
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: DeviceTypeService.isTv ? 0 : -10,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = AppColors.textSecondary,
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: imageHeight == null ? 0 : null,
              height: imageHeight,
              child: AspectRatio(
                aspectRatio: ratio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(
                        url:
                            customized &&
                                ui.homePosterShape == HomePosterShape.landscape
                            ? item.backdropUrl ?? item.posterUrl
                            : item.posterUrl,
                      ),
                      if (DeviceTypeService.isTv && item.voteAverage > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: RatingBadge(value: item.voteAverage),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RatingBadge extends StatelessWidget {
  final double value;

  const RatingBadge({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.overlayControl,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.secondary, size: 12),
          const SizedBox(width: 2),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Height of a horizontal row of [TmdbPosterCard]s that never clips the
/// three-line title, including the TV focus padding and system text scaling.
double tmdbPosterRowHeight(BuildContext context, {double mobile = 210}) {
  if (!DeviceTypeService.isTv) {
    if (HomePresentation.contains(context)) {
      final ui = context.watch<UiSettings>();
      return HomePresentation.width(context) / ui.homePosterShape.aspectRatio +
          (ui.homeTitles
              ? MediaQuery.textScalerOf(context).scale(12) * 2.2 + 18
              : 12);
    }
    return mobile;
  }
  final home = TvHomeLayout.maybeOf(context);
  if (home != null) return home.carouselHeight;
  final line = MediaQuery.textScalerOf(context).scale(14) * 1.2;
  // 112px poster (2:3) + title padding + three lines + list vertical padding.
  return 112 * 3 / 2 + 17 + line * 3 + 16 + 10;
}

/// A fixed title box keeps adjacent posters aligned; long names fit in full.
class TvPosterTitle extends StatelessWidget {
  const TvPosterTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(14) * 1.2 * 3;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, box) {
          var font = 14.0;
          TextStyle style() => TextStyle(
            fontSize: font,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          );
          TextPainter painter() => TextPainter(
            text: TextSpan(text: title, style: style()),
            maxLines: 3,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: box.maxWidth);
          var measured = painter();
          while (measured.didExceedMaxLines && font > 8) {
            measured.dispose();
            font -= 0.5;
            measured = painter();
          }
          final stillLong = measured.didExceedMaxLines;
          measured.dispose();
          if (stillLong) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: box.maxWidth,
                child: Text(title, style: style()),
              ),
            );
          }
          return Text(title, maxLines: 3, style: style());
        },
      ),
    );
  }
}
