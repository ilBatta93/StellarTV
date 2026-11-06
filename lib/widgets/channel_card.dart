import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import 'poster_card.dart';
import 'title_facets.dart';
import '../providers/history_provider.dart';
import '../providers/ui_settings.dart';

import 'package:provider/provider.dart';

import '../services/catalog_rating_service.dart';
import '../services/title_matching.dart';

class ChannelCard extends StatelessWidget {
  final Channel channel;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;
  final String? qualityLabel;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
    this.qualityLabel,
  });

  bool get _isLive => channel.type == ContentType.live;

  String get _title => _isLive ? channel.name : displayTitle(channel.name);

  Widget _artwork() => CatalogArtwork(
    channel: channel,
    fallbackLabel: DeviceTypeService.isTv ? _title : null,
  );

  @override
  Widget build(BuildContext context) {
    // Subscribes to the poster preferences; [_card] reads them.
    context.select<UiSettings, String>(
      (ui) =>
          '${ui.showRatings}${ui.showTitles}${ui.showQuality}'
          '${ui.favoriteHeart}${ui.posterCorners.name}',
    );
    if (DeviceTypeService.isTv && !_isLive) {
      return _TvRatedPoster(
        channel: channel,
        builder: (rating) => _card(context, rating),
      );
    }
    return _card(context, null);
  }

  Widget _card(BuildContext context, double? rating) {
    // Read, not selected: on TV this runs inside _TvRatedPoster's build;
    // [build] already subscribes to the corners.
    final radius = BorderRadius.circular(
      context.read<UiSettings>().posterCorners.radius,
    );
    return Pressable(
      onTap: onTap,
      onLongPress: onFavoriteTap,
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
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
                borderRadius: radius,
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
                      _artwork(),
                    if (isFavorite || context.read<UiSettings>().favoriteHeart)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _FavoriteButton(
                          isFavorite: isFavorite,
                          onTap: onFavoriteTap,
                        ),
                      ),
                    if (!_isLive && context.read<UiSettings>().showRatings)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: ChannelRatingBadge(channel, framed: true),
                      ),
                    if (!_isLive &&
                        qualityLabel != null &&
                        context.read<UiSettings>().showQuality)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: _QualityBadge(qualityLabel!),
                      ),
                    if (_isLive)
                      const Positioned(left: 6, bottom: 6, child: LiveBadge())
                    else
                      PosterProgressMark(channel),
                  ],
                ),
              ),
            ),
            if (_isLive || context.read<UiSettings>().showTitles)
              Padding(
                padding: DeviceTypeService.isTv
                    ? const EdgeInsets.fromLTRB(9, 8, 9, 9)
                    : const EdgeInsets.only(top: 8),
                child: DeviceTypeService.isTv
                    ? TvPosterTitle(_title)
                    : Text(
                        _title,
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

/// Poster of a film or series in every catalog layout: provider artwork
/// first, then the official TMDB poster, then the audiobook cover or the
/// neutral icon.
class CatalogArtwork extends StatelessWidget {
  const CatalogArtwork({super.key, required this.channel, this.fallbackLabel});

  final Channel channel;
  final String? fallbackLabel;

  static const _audiobookCover = 'assets/images/audiobook_cover.jpg';

  @override
  Widget build(BuildContext context) {
    final audiobook = isAudiobook(channel.name, channel.group);
    final tmdb = audiobook
        ? null
        : CatalogRatingService.instance.itemOf(channel)?.posterUrl;
    final icon =
        channel.type == ContentType.series || channel.type == ContentType.anime
        ? Icons.video_library_outlined
        : Icons.movie_outlined;
    if (channel.logo.isEmpty && tmdb == null && audiobook) {
      return Image.asset(_audiobookCover, fit: BoxFit.cover, cacheWidth: 360);
    }
    return PosterImage(
      url: channel.logo.isEmpty ? tmdb : channel.logo,
      fallbackUrls: [if (tmdb != null && channel.logo.isNotEmpty) tmdb],
      fallbackIcon: icon,
      audiobookCover: audiobook ? _audiobookCover : null,
      fallbackLabel: fallbackLabel,
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

class _QualityBadge extends StatelessWidget {
  final String label;
  const _QualityBadge(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.overlayControl,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: AppColors.primary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
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

  /// The TMDB poster often arrives after the rating (already known from the
  /// cloud): comparing the rating alone left those cards grey until they
  /// were rebuilt, e.g. by opening the title and coming back.
  String? _poster;
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
    final service = CatalogRatingService.instance;
    _rating = service.ratingOf(widget.channel);
    _poster = service.itemOf(widget.channel)?.posterUrl;
    service.request([widget.channel], priority: true);
  }

  void _changed() {
    final service = CatalogRatingService.instance;
    final rating = service.ratingOf(widget.channel);
    final poster = service.itemOf(widget.channel)?.posterUrl;
    if (!mounted || (rating == _rating && poster == _poster)) return;
    setState(() {
      _rating = rating;
      _poster = poster;
    });
  }

  @override
  void dispose() {
    CatalogRatingService.instance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_rating);
}

/// Progress bar of a started title and a mark on a watched one, drawn over
/// the poster's bottom edge. Rebuilds only when this title's mark changes.
class PosterProgressMark extends StatelessWidget {
  const PosterProgressMark(this.channel, {super.key});
  final Channel channel;

  static PosterProgress? _of(BuildContext context, Channel channel) {
    if (channel.type == ContentType.live ||
        !context.select<UiSettings, bool>((ui) => ui.posterProgress)) {
      return null;
    }
    try {
      return context.select<HistoryProvider, PosterProgress?>(
        (h) => h.posterProgressFor(channel),
      );
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mark = _of(context, channel);
    if (mark == null) return const SizedBox.shrink();
    final tv = DeviceTypeService.isTv;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!mark.watched)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: tv ? 5 : 4,
            child: ColoredBox(
              color: AppColors.overlayControl,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: mark.progress.clamp(0.04, 1.0),
                child: ColoredBox(color: AppColors.primary),
              ),
            ),
          )
        else
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: tv ? 16 : 14,
                color: AppColors.textPrimary,
                semanticLabel: 'Visto',
              ),
            ),
          ),
      ],
    );
  }
}
