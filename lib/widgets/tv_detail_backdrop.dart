import "package:cached_network_image/cached_network_image.dart";
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// TV only: movie/series page with the backdrop filling the whole screen and
/// staying still behind the content (no picture cut at the top while
/// scrolling). Soft shadows on the left and at the bottom keep the text
/// readable.
class TvDetailBackdrop extends StatelessWidget {
  final String? image;
  final Widget child;

  const TvDetailBackdrop({super.key, required this.image, required this.child});

  /// Space above the title, so the first screen shows the picture like the
  /// Home banner.
  static double topSpace(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.30).clamp(120.0, 320.0);

  @override
  Widget build(BuildContext context) {
    final url = image?.replaceFirst('/t/p/w780/', '/t/p/w1280/');
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
                if (url != null && url.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 1280,
                    placeholder: (_, _) => const SizedBox.expand(),
                    errorWidget: (_, _, _) => const SizedBox.expand(),
                    fadeInDuration: const Duration(milliseconds: 300),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xF209090D),
                        Color(0xB309090D),
                        Color(0x3309090D),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x6609090D),
                        Color(0x0009090D),
                        Color(0xCC09090D),
                        AppColors.background,
                      ],
                      stops: [0, 0.25, 0.75, 1],
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
