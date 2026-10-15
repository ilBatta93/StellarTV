import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import 'poster_card.dart';
import '../services/catalog_rating_service.dart';

class ChannelCard extends StatelessWidget {
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  bool get _isLive => channel.type == ContentType.live;

  @override
  Widget build(BuildContext context) {
    if (DeviceTypeService.isTv && !_isLive) {
      return _TvRatedPoster(
        channel: channel,
        builder: (rating) => _card(context, rating),
      );
    }
    return _card(context, null);
  }

  Widget _card(BuildContext context, double? rating) {
    return Pressable(
      onTap: onTap,
      onLongPress: onFavoriteTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: DeviceTypeService.isTv ? AppColors.surface : null,
          border: Border.all(
            color: DeviceTypeService.isTv ? AppColors.clear : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isLive)
                      Container(
                        color: AppColors.card,
                        padding: const EdgeInsets.all(16),
                        child: PosterImage(
                          url: channel.logo,
                          fit: BoxFit.contain,
                          fallbackIcon: Icons.live_tv_rounded,
                        ),
                      )
                    else
                      PosterImage(
                        url: channel.logo,
                        fallbackIcon:
                            channel.type == ContentType.series ||
                                channel.type == ContentType.anime
                            ? Icons.video_library_outlined
                            : Icons.movie_outlined,
                      ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _FavoriteButton(
                        isFavorite: isFavorite,
                        onTap: onFavoriteTap,
                      ),
                    ),
                    if (rating != null && rating > 0)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: RatingBadge(value: rating),
                      ),
                    if (_isLive)
                      const Positioned(left: 6, bottom: 6, child: LiveBadge()),
                  ],
                ),
              ),
            ),
            Padding(
              padding: DeviceTypeService.isTv
                  ? const EdgeInsets.fromLTRB(9, 8, 9, 9)
                  : const EdgeInsets.only(top: 8),
              child: Text(
                channel.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: DeviceTypeService.isTv ? 15 : 12,
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

class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;

  const _FavoriteButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.overlayControl,
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(isFavorite),
            color: isFavorite ? AppColors.primary : AppColors.textPrimary,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TvRatedPoster extends StatefulWidget {
  final Channel channel;
  final Widget Function(double?) builder;
  const _TvRatedPoster({required this.channel, required this.builder});
  @override
  State<_TvRatedPoster> createState() => _TvRatedPosterState();
}

class _TvRatedPosterState extends State<_TvRatedPoster> {
  double? _rating;
  @override
  void initState() {
    super.initState();
    CatalogRatingService.instance.addListener(_changed);
    _request();
  }

  @override
  void didUpdateWidget(covariant _TvRatedPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) _request();
  }

  void _request() {
    _rating = CatalogRatingService.instance.ratingOf(widget.channel);
    CatalogRatingService.instance.request([widget.channel], priority: true);
  }

  void _changed() {
    final value = CatalogRatingService.instance.ratingOf(widget.channel);
    if (mounted && value != _rating) setState(() => _rating = value);
  }

  @override
  void dispose() {
    CatalogRatingService.instance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_rating);
}
