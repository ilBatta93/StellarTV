import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tmdb_item.dart';
import '../providers/ui_settings.dart';
import '../theme/app_theme.dart';

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
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, _) => Container(color: AppColors.card),
      errorWidget: (_, _, _) => fallback,
    );
  }
}

class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final animations = context.watch<UiSettings>().animations;
    return GestureDetector(
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
  }
}

class TmdbPosterCard extends StatelessWidget {
  final TmdbItem item;
  final VoidCallback onTap;
  final double width;

  const TmdbPosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 120,
  });

  @override
  Widget build(BuildContext context) {
    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PosterImage(url: item.posterUrl),
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
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: fillsCell ? null : width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fillsCell)
              Expanded(child: poster)
            else
              AspectRatio(aspectRatio: 2 / 3, child: poster),
            const SizedBox(height: 8),
            Text(
              item.title,
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

class RankedPosterCard extends StatelessWidget {
  final TmdbItem item;
  final int rank;
  final VoidCallback onTap;

  const RankedPosterCard({
    super.key,
    required this.item,
    required this.rank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: rank >= 10 ? 196 : 172,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: -18,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 128,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -10,
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
              bottom: 0,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: PosterImage(url: item.posterUrl),
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
        color: Colors.black.withValues(alpha: 0.7),
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
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
