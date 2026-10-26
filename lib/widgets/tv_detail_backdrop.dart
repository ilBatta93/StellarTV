import '../services/image_cache_service.dart';
import '../services/image_warmup_service.dart';
import '../services/tv_render_policy.dart';

import "package:cached_network_image/cached_network_image.dart";
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// TV only: movie, series and person pages fill the screen with a still
/// backdrop (no picture cut at the top while scrolling). Decode and the
/// requested width follow [TvRenderPolicy], the same ceilings as Home.
/// The artwork stays visible past mid-screen. Black covers only the text
/// side: the left edge, and the bottom of the page.
class TvDetailBackdrop extends StatelessWidget {
  final String? image;
  final Widget child;

  const TvDetailBackdrop({super.key, required this.image, required this.child});

  /// Small space above the title: the picture stays visible behind it, but
  /// the content starts near the top so more of the page fits on screen.
  static double topSpace(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.08).clamp(40.0, 100.0);

  /// Rewrites only a published TMDB width. Other artwork is left as-is.
  static String? requestUrl(String? image, int requestWidth) {
    if (image == null || image.isEmpty || requestWidth <= 0) return null;
    return image.replaceFirst(RegExp(r'/t/p/w\d+/'), '/t/p/w$requestWidth/');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final physical = (width * pixelRatio).round();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Own layer: scrolling the page never repaints the picture.
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: TvImageMemoryGuard.reducedRendering,
                  builder: (_, pressure, _) {
                    final cap = TvRenderPolicy.backdropDecodeLimit(
                      memoryPressure: pressure,
                    );
                    final decodeWidth = physical > 0 && physical < cap
                        ? physical
                        : cap;
                    final url = requestUrl(
                      image,
                      TvRenderPolicy.backdropRequestWidth(
                        memoryPressure: pressure,
                      ),
                    );
                    if (url == null) return const SizedBox.expand();
                    return CachedNetworkImage(
                      cacheManager: AppImageCache.manager,
                      imageUrl: url,
                      fit: BoxFit.cover,
                      memCacheWidth: decodeWidth,
                      placeholder: (_, _) => const SizedBox.expand(),
                      errorWidget: (_, _, _) => const SizedBox.expand(),
                      fadeInDuration: const Duration(milliseconds: 300),
                    );
                  },
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.background,
                        AppColors.background,
                        AppColors.clear,
                      ],
                      stops: [0, 0.28, 0.58],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.clear,
                        AppColors.clear,
                        AppColors.background,
                      ],
                      stops: [0, 0.55, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
