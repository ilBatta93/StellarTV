import 'package:flutter/material.dart';
import 'brand_logo.dart';

/// Timeline contains no startup, session or navigation work.
class BrandIntroFrame {
  const BrandIntroFrame(this.symbol, this.shift, this.stellar, this.tv);
  final double symbol;
  final double shift;
  final double stellar;
  final double tv;
  static double _phase(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);
  static BrandIntroFrame at(double t) => BrandIntroFrame(
    _phase(t, 0, .18),
    Curves.easeInOutCubic.transform(_phase(t, .25, .60)),
    _phase(t, .60, .80),
    _phase(t, .80, 1),
  );
}

/// Approved logo assembled from its three vectors (star, STELLAR, TV), each
/// placed at its exact position in the shared artwork; presentation-only.
class BrandIntro extends StatelessWidget {
  const BrandIntro({super.key, required this.progress});
  final double progress;

  static Widget _part(String asset, BrandBox b, double scale, double left, double opacity) =>
      Positioned(
        left: left,
        top: (b.y - kBrandFullBox.y) * scale,
        child: Opacity(
          opacity: opacity,
          child: brandArt(asset, b.w * scale, b.h * scale, ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final frame = BrandIntroFrame.at(progress);
    return Semantics(
      label: 'STELLAR TV',
      image: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth.clamp(0.0, 720.0);
            final full = kBrandFullBox;
            final scale = width / full.w;
            double at(BrandBox b) => (b.x - full.x) * scale;
            final centred = (width - kBrandStarBox.w * scale) / 2;
            return SizedBox(
              width: width,
              height: full.h * scale,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _part(kBrandSymbolAsset, kBrandStarBox, scale,
                      centred * (1 - frame.shift) + at(kBrandStarBox) * frame.shift, frame.symbol),
                  _part(kBrandStellarAsset, kBrandStellarBox, scale, at(kBrandStellarBox), frame.stellar),
                  _part(kBrandTvAsset, kBrandTvBox, scale, at(kBrandTvBox), frame.tv),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
