import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import 'poster_card.dart';
import 'poster_overlay.dart';
import '../models/poster_badges.dart';
import 'title_facets.dart';
import '../providers/history_provider.dart';
import '../providers/ui_settings.dart';

import 'package:provider/provider.dart';

import '../services/catalog_rating_service.dart';
import '../models/title_credits.dart' show formatRuntime;
import '../services/title_matching.dart';
import '../services/title_runtime_store.dart';

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

  Widget _artwork(bool overlayTitle) => CatalogArtwork(
    channel: channel,
    fallbackLabel: DeviceTypeService.isTv && !overlayTitle ? _title : null,
  );

  @override
  Widget build(BuildContext context) {
    // Subscribes to the poster preferences; [_card] reads them.
    context.select<UiSettings, String>(
      (ui) =>
          '${ui.showRatings}${ui.titlePlacement.name}${ui.showQuality}'
          '${ui.favoriteHeart}${ui.posterCorners.name}${ui.posterDetails}'
          '${ui.badgeNew}${ui.badgePlatform}',
    );
    if (DeviceTypeService.isTv && !_isLive) {
      return _TvRatedPoster(
        channel: channel,
        builder: (rating) => _card(context, rating),
      );
    }
    return _card(context, null);
  }

  /// Badges in their fixed places (see [PosterSlot]).
  Widget _overlay(UiSettings ui, {required bool overlayTitle}) {
    final tv = DeviceTypeService.isTv;
    if (_isLive) {
      return PosterOverlay(
        topRight: [
          if (isFavorite || ui.favoriteHeart)
            _FavoriteButton(isFavorite: isFavorite, onTap: onFavoriteTap),
        ],
        bottomLeft: const [LiveBadge()],
      );
    }
    return PosterOverlay(
      topLeft: [
        if (ui.showRatings) ChannelRatingBadge(channel, framed: true),
        if (ui.badgeNew) PosterNewBadge(channel),
      ],
      topRight: [
        if (isFavorite || ui.favoriteHeart)
          _FavoriteButton(isFavorite: isFavorite, onTap: onFavoriteTap),
      ],
      bottomLeft: [
        if (qualityLabel != null && ui.showQuality)
          _QualityBadge(qualityLabel!),
        if (ui.badgePlatform)
          PosterPlatformBadge(channel, height: tv ? 18 : 16),
      ],
      bottomRight: [
        PosterProgressMark(channel, part: PosterProgressPart.check),
      ],
      edge: PosterProgressMark(channel, part: PosterProgressPart.bar),
      edgeHeight: tv ? 5 : 4,
      caption: overlayTitle ? _caption(ui) : null,
    );
  }

  /// Title written on the poster ("Titoli: Sulla locandina").
  Widget _caption(UiSettings ui) {
    final tv = DeviceTypeService.isTv;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: tv ? 15 : 12.5,
            fontWeight: FontWeight.w700,
            height: 1.15,
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4)],
          ),
        ),
        if (ui.posterDetails) PosterDetailsLine(channel, onArt: true),
      ],
    );
  }

  Widget _card(BuildContext context, double? rating) {
    // Read, not selected: on TV this runs inside _TvRatedPoster's build;
    // [build] already subscribes to the poster preferences.
    final ui = context.read<UiSettings>();
    final radius = BorderRadius.circular(ui.posterCorners.radius);
    final placement = _isLive ? TitlePlacement.below : ui.titlePlacement;
    final overlayTitle = placement == TitlePlacement.overlay;
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
                      _artwork(overlayTitle),
                    _overlay(ui, overlayTitle: overlayTitle),
                  ],
                ),
              ),
            ),
            if (placement == TitlePlacement.below)
              Padding(
                padding: DeviceTypeService.isTv
                    ? const EdgeInsets.fromLTRB(9, 8, 9, 9)
                    : const EdgeInsets.only(top: 8),
                child: !_isLive && ui.posterDetails
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DeviceTypeService.isTv
                              ? TvPosterTitle(_title)
                              : _titleText(maxLines: 1),
                          PosterDetailsLine(channel),
                        ],
                      )
                    : DeviceTypeService.isTv
                    ? TvPosterTitle(_title)
                    : _titleText(maxLines: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _titleText({required int maxLines}) => Text(
    _title,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: AppColors.textPrimary,
      fontSize: DeviceTypeService.isTv ? 15 : 12,
      fontWeight: DeviceTypeService.isTv ? FontWeight.w700 : FontWeight.w600,
      height: DeviceTypeService.isTv ? 1.2 : 1.1,
      shadows: [
        Shadow(
          color: AppColors.overlay,
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ],
    ),
  );
}

/// "2019 · 1 h 47 min", "2021 · ep. 52 min", or what is known of the two.
String posterDetailsLabel({int? year, int? minutes, bool series = false}) {
  final parts = [
    if (year != null && year > 0) '$year',
    if (minutes != null && minutes > 0)
      series ? 'ep. ${formatRuntime(minutes)}' : formatRuntime(minutes),
  ];
  return parts.join(' · ');
}

/// Release year of a catalog title: provider date or year in the name,
/// then the TMDB identity already stored. No network.
int? posterYearOf(Channel channel) {
  final key = channel.releaseKey;
  if (key > 0) return key ~/ 10000;
  final date = CatalogRatingService.instance.itemOf(channel)?.releaseDate;
  if (date == null || date.length < 4) return null;
  final year = int.tryParse(date.substring(0, 4));
  return year != null && year > 1900 ? year : null;
}

/// Year and length under a catalog title ("Anno e durata sotto il titolo").
/// Always one line high, so posters in a row stay aligned while lengths
/// are still unknown.
class PosterDetailsLine extends StatelessWidget {
  const PosterDetailsLine(this.channel, {super.key, this.onArt = false});
  final Channel channel;

  /// Written over the poster's dark fade instead of the card background.
  final bool onArt;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    final size = tv ? 12.5 : 10.5;
    final height = MediaQuery.textScalerOf(context).scale(size) * 1.25;
    final store = TitleRuntimeStore.instance.store;
    return SizedBox(
      height: height + (tv ? 2 : 1),
      width: double.infinity,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Padding(
          padding: EdgeInsets.only(top: tv ? 2 : 1),
          child: Text(
            posterDetailsLabel(
              year: posterYearOf(channel),
              minutes: TitleRuntimeStore.instance.minutesOf(channel),
              series: channel.type != ContentType.movie,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size,
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: onArt ? const Color(0xE6FFFFFF) : AppColors.textSecondary,
            ),
          ),
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
/// Which piece of the progress mark to draw: [PosterOverlay] puts the bar
/// on the bottom edge and the watched mark in the bottom-right corner.
enum PosterProgressPart { all, bar, check }

class PosterProgressMark extends StatelessWidget {
  const PosterProgressMark(
    this.channel, {
    super.key,
    this.part = PosterProgressPart.all,
  });
  final Channel channel;
  final PosterProgressPart part;

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
    if (part == PosterProgressPart.bar) {
      return mark.watched ? const SizedBox.shrink() : _bar(mark, tv);
    }
    if (part == PosterProgressPart.check) {
      return mark.watched ? _check(tv) : const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!mark.watched)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: tv ? 5 : 4,
            child: _bar(mark, tv),
          )
        else
          Positioned(right: 6, bottom: 6, child: _check(tv)),
      ],
    );
  }

  static Widget _bar(PosterProgress mark, bool tv) => ColoredBox(
    color: AppColors.overlayControl,
    child: FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: mark.progress.clamp(0.04, 1.0),
      child: ColoredBox(color: AppColors.primary),
    ),
  );

  static Widget _check(bool tv) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
    child: Icon(
      Icons.check_rounded,
      size: tv ? 16 : 14,
      color: AppColors.textPrimary,
      semanticLabel: 'Visto',
    ),
  );
}
