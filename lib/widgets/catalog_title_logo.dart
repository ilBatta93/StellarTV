import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/tmdb_item.dart';
import '../providers/discover_provider.dart';
import '../providers/ui_settings.dart';
import '../services/catalog_rating_service.dart';
import '../services/image_cache_service.dart';
import '../services/title_facet_index.dart';

/// "Logo al posto del titolo" in catalogs: the title's logo artwork where
/// the name would be written, else [fallback].
///
/// Places that show many covers at once leave [fetch] off and only use a
/// logo the device already knows (no request per card). Places that show
/// one title at a time (In evidenza, the TV "Muro" strip) may ask for it,
/// through the same shared cache as the Home banner.
class CatalogTitleLogo extends StatefulWidget {
  const CatalogTitleLogo({
    super.key,
    required this.channel,
    required this.fallback,
    required this.height,
    this.fetch = false,
    this.alignment = Alignment.centerLeft,
    this.decodeWidth = 360,
  });

  final Channel channel;
  final Widget fallback;
  final double height;
  final bool fetch;
  final Alignment alignment;
  final int decodeWidth;

  /// TMDB identity already on the device for [channel].
  static TmdbItem? itemOf(Channel channel) =>
      CatalogRatingService.instance.itemOf(channel);

  /// The logo the device already knows: null when none is known (yet).
  static String? knownLogo(Channel channel) {
    final item = itemOf(channel);
    if (item == null || item.id <= 0) return null;
    final media = '${item.isMovie ? 'movie' : 'tv'}:${item.id}';
    return TitleFacetIndex.instance.logoOf(media)?.url;
  }

  @override
  State<CatalogTitleLogo> createState() => _CatalogTitleLogoState();
}

class _CatalogTitleLogoState extends State<CatalogTitleLogo> {
  Future<String?>? _requested;
  String? _for;

  /// Asked once per title, and only while the option is on: turning it on
  /// later still finds the title unrequested.
  Future<String?>? _request() {
    final id = widget.channel.id;
    if (_for == id) return _requested;
    _for = id;
    _requested = null;
    final item = CatalogTitleLogo.itemOf(widget.channel);
    final discover = Provider.of<DiscoverProvider?>(context, listen: false);
    if (item != null && discover != null) {
      _requested = discover.tmdb.titleLogo(item);
    }
    return _requested;
  }

  Widget _image(String url) => Semantics(
    label: widget.channel.displaySeriesName,
    image: true,
    child: CachedNetworkImage(
      cacheManager: AppImageCache.manager,
      imageUrl: url,
      height: widget.height,
      fit: BoxFit.contain,
      alignment: widget.alignment,
      memCacheWidth: widget.decodeWidth,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => widget.fallback,
      errorWidget: (_, _, _) => widget.fallback,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final on = context.select<UiSettings, bool>(
      (ui) => ui.titleLogos && ui.showPosters,
    );
    if (!on) return widget.fallback;
    final known = CatalogTitleLogo.knownLogo(widget.channel);
    if (known != null) return _image(known);
    final requested = widget.fetch ? _request() : null;
    if (requested == null) return widget.fallback;
    return FutureBuilder<String?>(
      future: requested,
      builder: (context, snapshot) {
        final url = snapshot.data;
        // The written title stays until the logo is there.
        return url == null ? widget.fallback : _image(url);
      },
    );
  }
}
