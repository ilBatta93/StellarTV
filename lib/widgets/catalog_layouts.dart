import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ui_settings.dart';

import '../models/channel.dart';
import '../services/catalog_builder.dart';
import '../services/catalog_rating_service.dart';
import 'title_facets.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import 'channel_card.dart';
import 'poster_card.dart';
import 'poster_overlay.dart';
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
    final ui = context.watch<UiSettings>();
    final quality = ui.showQuality
        ? CatalogBuilder.qualityLabel(channel.name)
        : null;
    // Wide covers: the standard style keeps its 14 px corners.
    final radius = posterRadius(context, scale: 1.4);
    Widget card(String? scene) => ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (scene != null) ...[
            // The scene still fills the wide tile; the text sits on a dark
            // fade so it stays readable on bright frames.
            CatalogSceneImage(url: scene),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Colors.transparent, AppColors.overlay],
                  stops: [0.25, 1],
                ),
              ),
            ),
          ] else ...[
            // Blurred-looking fill plus the full poster on the left: posters
            // are vertical, so they are framed instead of cropped badly.
            if (!tv)
              Opacity(opacity: 0.35, child: CatalogArtwork(channel: channel)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppColors.overlay, AppColors.background],
                ),
              ),
            ),
          ],
          Row(
            children: [
              if (scene == null)
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: CatalogArtwork(channel: channel),
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
                          if (ui.showRatings) ChannelRatingBadge(channel),
                          if (ui.badgeNew) PosterNewBadge(channel),
                          if (quality != null) _Chip(quality),
                          if (ui.badgePlatform) PosterPlatformBadge(channel),
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
          PosterProgressMark(channel),
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
    final content = ui.sceneArt
        ? CatalogScene(channel: channel, builder: card)
        : card(null);
    if (tv) {
      return TvFocusable(
        borderRadius: radius,
        onPressed: onTap,
        onLongPress: onFavoriteTap,
        child: content,
      );
    }
    return Pressable(
      onTap: onTap,
      onLongPress: onFavoriteTap,
      borderRadius: radius,
      child: content,
    );
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
    final sceneArt = context.select<UiSettings, bool>((ui) => ui.sceneArt);
    // One header at a time, so the scene still is shown on TV as well.
    Widget backdrop(String? scene) => scene != null
        ? Stack(
            fit: StackFit.expand,
            children: [
              CatalogSceneImage(url: scene),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [Colors.transparent, AppColors.overlay],
                    stops: [0, 0.75],
                  ),
                ),
              ),
            ],
          )
        : tv
        ? const SizedBox.shrink()
        : Opacity(opacity: 0.18, child: CatalogArtwork(channel: channel));
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
          if (sceneArt)
            CatalogScene(channel: channel, builder: backdrop)
          else
            backdrop(null),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: posterRadius(context),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: CatalogArtwork(channel: channel),
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
                          if (context.select<UiSettings, bool>(
                            (ui) => ui.badgeNew,
                          ))
                            PosterNewBadge(channel),
                          if (quality != null) _Chip(quality),
                          if (context.select<UiSettings, bool>(
                            (ui) => ui.badgePlatform,
                          ))
                            PosterPlatformBadge(channel),
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

/// Scene still of a catalog title from the identity already on the device:
/// no request per card. Rebuilds only when this title's still changes.
class CatalogScene extends StatefulWidget {
  const CatalogScene({super.key, required this.channel, required this.builder});

  final Channel channel;
  final Widget Function(String? sceneUrl) builder;

  static String? sceneOf(Channel channel) =>
      CatalogRatingService.instance.itemOf(channel)?.sceneUrl;

  @override
  State<CatalogScene> createState() => _CatalogSceneState();
}

class _CatalogSceneState extends State<CatalogScene> {
  final _identities = CatalogRatingService.instance.identities;
  late String? _scene = CatalogScene.sceneOf(widget.channel);

  @override
  void initState() {
    super.initState();
    _identities.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant CatalogScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _scene = CatalogScene.sceneOf(widget.channel);
    }
  }

  void _changed() {
    final value = CatalogScene.sceneOf(widget.channel);
    if (!mounted || value == _scene) return;
    setState(() => _scene = value);
  }

  @override
  void dispose() {
    _identities.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_scene);
}

/// Wide scene still, decoded at the tile size like the posters.
class CatalogSceneImage extends StatelessWidget {
  const CatalogSceneImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => PosterImage(
    url: url,
    fallbackIcon: Icons.movie_outlined,
    maxDecodeWidth: 780,
  );
}
